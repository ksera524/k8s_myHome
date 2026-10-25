#!/usr/bin/env python3
"""新イメージ用の切替マニフェストを生成する。applyや既存Applicationの変更は行わない。"""
import argparse
import copy
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
DB_LABEL = 'database.k8s-myhome.local/shared-postgresql'


def load(app):
    return list(yaml.safe_load_all((ROOT / f'manifests/apps/{app}/manifest.yaml').read_text()))


def emit(base, app, docs):
    output = base / app
    output.mkdir(parents=True, exist_ok=True)
    (output / 'manifest.yaml').write_text(yaml.safe_dump_all(docs, sort_keys=False, allow_unicode=True))
    (output / 'kustomization.yaml').write_text('apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n  - manifest.yaml\n')


def container(name, image, binary, args):
    return {'name': name, 'image': image, 'command': [binary], 'args': args,
            'env': [], 'resources': {'requests': {'cpu': '50m', 'memory': '128Mi'},
                                    'limits': {'cpu': '300m', 'memory': '512Mi'}},
            'securityContext': {'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True,
                                'capabilities': {'drop': ['ALL']}}}


def pg(c, database, maximum=2):
    c.setdefault('envFrom', []).extend([{'configMapRef': {'name': 'application-postgresql'}},
                                       {'secretRef': {'name': 'application-postgresql'}}])
    c.setdefault('env', []).extend([{'name': 'PGDATABASE', 'value': database},
                                   {'name': 'PGPOOL_MAX', 'value': str(maximum)}])
    c.setdefault('volumeMounts', []).append({'name': 'database-ca', 'mountPath': '/etc/postgresql', 'readOnly': True})


def pod(app, containers):
    return {'metadata': {'labels': {'app': app, DB_LABEL: 'true'}}, 'spec': {
        'automountServiceAccountToken': False,
        'imagePullSecrets': [{'name': 'harbor-registry'}],
        'securityContext': {'runAsNonRoot': True, 'runAsUser': 1000, 'runAsGroup': 1000,
                            'fsGroup': 1000, 'seccompProfile': {'type': 'RuntimeDefault'}},
        'containers': containers,
        'volumes': [{'name': 'database-ca', 'configMap': {'name': 'shared-postgresql-ca'}}]}}


def deployment(name, containers, recreate=False):
    spec = {'replicas': 1, 'selector': {'matchLabels': {'app': name}}, 'template': pod(name, containers)}
    if name == 'api-hub-notification-worker':
        spec['template']['spec']['terminationGracePeriodSeconds'] = 90
    if name in {'media-api', 'hitomi-outbox'}:
        port = '9090' if name == 'hitomi-outbox' else '3000'
        spec['template']['metadata']['annotations'] = {
            'prometheus.io/scrape': 'true', 'prometheus.io/port': port, 'prometheus.io/path': '/metrics'}
    if recreate:
        spec['strategy'] = {'type': 'Recreate'}
    return {'apiVersion': 'apps/v1', 'kind': 'Deployment', 'metadata': {'name': name, 'namespace': 'sandbox', 'annotations': {'reloader.stakater.com/auto': 'true'}}, 'spec': spec}


def migration(app, image, binary, database):
    c = container('migrate', image, binary, ['--migrate'])
    pg(c, database, 1)
    template = pod(f'{app}-migration', [c])
    template['spec']['restartPolicy'] = 'Never'
    return {'apiVersion': 'batch/v1', 'kind': 'Job', 'metadata': {'name': f'{app}-migration', 'namespace': 'sandbox',
            'annotations': {'argocd.argoproj.io/hook': 'PreSync', 'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation,HookSucceeded'}},
            'spec': {'backoffLimit': 6, 'activeDeadlineSeconds': 900, 'template': template}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image-tag', default='architecture-20261024')
    parser.add_argument('--output', type=Path, default=ROOT / 'automation/examples/application-architecture')
    args = parser.parse_args()
    image = lambda name: f'harbor.qroksera.com/sandbox/{name}:{args.image_tag}'

    # api-hubのServiceがworkerを選択しないよう、appラベルを必ず別にする。
    api = load('api-hub')
    api_deploy = next(d for d in api if d and d['kind'] == 'Deployment')
    template = api_deploy['spec']['template']
    template['spec']['terminationGracePeriodSeconds'] = 90
    template['metadata'].setdefault('annotations', {}).update({
        'prometheus.io/scrape': 'true', 'prometheus.io/port': '3000', 'prometheus.io/path': '/metrics'})
    template['metadata']['labels'][DB_LABEL] = 'true'
    c = template['spec']['containers'][0]
    c['image'] = image('api-hub')
    c['env'].append({'name': 'RUSTFS_S3_BROWSER_ENDPOINT', 'value': 'https://s3.internal.qroksera.com'})
    pg(c, 'api_hub', 3)
    template['spec'].setdefault('volumes', []).append({'name': 'database-ca', 'configMap': {'name': 'shared-postgresql-ca'}})
    worker = copy.deepcopy(c)
    worker['name'] = 'notification-worker'
    worker['args'] = ['--notification-worker']
    for key in ['ports', 'livenessProbe', 'readinessProbe', 'startupProbe']:
        worker.pop(key, None)
    next(e for e in worker['env'] if e['name'] == 'PGPOOL_MAX')['value'] = '2'
    emit(args.output, 'api-hub', [migration('api-hub', image('api-hub'), '/api-hub', 'api_hub'), *api,
                                deployment('api-hub-notification-worker', [worker], True)])

    def media(mode, maximum=2):
        c = container(mode, image('hitomi-pdf-batch'), '/app/hitomi-pdf-batch', [f'--{mode}'])
        c['env'] = [{'name': 'WRAPPER_API_BASE_URL', 'value': 'http://api-hub.sandbox.svc:3000'},
                    {'name': 'RUSTFS_S3_BUCKET', 'value': 'pdfs'}, {'name': 'TZ', 'value': 'Asia/Tokyo'},
                    {'name': 'PUBLIC_API_BASE_URL', 'value': 'https://api-hub.internal.qroksera.com'},
                    {'name': 'MEDIA_DIRECT_DELIVERY', 'value': 'true'}]
        pg(c, 'media', maximum)
        return c

    api_c = media('serve', 3)
    api_c['ports'] = [{'containerPort': 3000}]
    api_c['readinessProbe'] = {'httpGet': {'path': '/ready', 'port': 3000}, 'periodSeconds': 10}
    api_c['livenessProbe'] = {'httpGet': {'path': '/health', 'port': 3000}, 'periodSeconds': 15}
    worker_c = media('worker')
    worker_c['volumeMounts'].append({'name': 'tmp', 'mountPath': '/tmp'})
    worker_c['resources']['requests']['ephemeral-storage'] = '1Gi'
    worker_c['resources']['limits']['ephemeral-storage'] = '6Gi'
    worker_d = deployment('hitomi-pdf-monitor', [worker_c], True)
    worker_d['metadata']['name'] = 'media-worker'
    worker_d['spec']['template']['spec']['volumes'].append({'name': 'tmp', 'emptyDir': {'sizeLimit': '5Gi'}})
    cron = next(d for d in load('hitomi-pdf') if d and d['kind'] == 'CronJob')
    cron['spec'].update({'schedule': '50 0,7 * * *', 'timeZone': 'Asia/Tokyo', 'suspend': True})
    cron['spec']['jobTemplate']['spec']['template'] = pod('hitomi-pdf-monitor', [media('plan')])
    cron['spec']['jobTemplate']['spec']['template']['spec']['restartPolicy'] = 'Never'
    reconcile = copy.deepcopy(cron)
    reconcile['metadata']['name'] = 'media-reconcile'
    reconcile['spec'].update({'schedule': '20 * * * *', 'suspend': False})
    reconcile['spec']['jobTemplate']['spec']['template']['spec']['containers'] = [media('reconcile')]
    service = {'apiVersion': 'v1', 'kind': 'Service', 'metadata': {'name': 'media-api', 'namespace': 'sandbox'},
               'spec': {'selector': {'app': 'media-api'}, 'ports': [{'port': 3000, 'targetPort': 3000}]}}
    emit(args.output, 'hitomi-pdf', [migration('media', image('hitomi-pdf-batch'), '/app/hitomi-pdf-batch', 'media'),
                                   cron, deployment('media-api', [api_c]), worker_d, service, reconcile])

    hitomi = load('hitomi')
    for cron in hitomi:
        if not cron or cron.get('kind') != 'CronJob':
            continue
        cron['spec']['timeZone'] = 'Asia/Tokyo'
        cron['spec']['schedule'] = '55 2,6,10,14,18,22 * * *'
        template = cron['spec']['jobTemplate']['spec']['template']
        template['metadata']['labels'][DB_LABEL] = 'true'
        c = template['spec']['containers'][0]
        c['image'] = image('hitomi')
        c.setdefault('env', []).append({'name': 'WRAPPER_API_BASE_URL', 'value': 'http://api-hub.sandbox.svc:3000'})
        pg(c, 'hitomi')
        template['spec'].setdefault('volumes', []).append({'name': 'database-ca', 'configMap': {'name': 'shared-postgresql-ca'}})
    outbox = container('outbox', image('hitomi'), '/app/hitomi', ['--dispatch'])
    outbox['ports'] = [{'name': 'metrics', 'containerPort': 9090}]
    outbox['env'] = [{'name': 'WRAPPER_API_BASE_URL', 'value': 'http://api-hub.sandbox.svc:3000'}]
    pg(outbox, 'hitomi')
    emit(args.output, 'hitomi', [migration('hitomi', image('hitomi'), '/app/hitomi', 'hitomi'), *hitomi,
                               deployment('hitomi-outbox', [outbox], True)])

    legacy = load('home-camera')
    for doc in legacy:
        if doc and doc.get('kind') == 'CronJob':
            doc['spec']['suspend'] = True
    recorder = container('recorder', image('home-camera'), '/usr/local/bin/home-camera', ['--record'])
    common = [{'name': 'API_HUB_BASE_URL', 'value': 'http://api-hub.sandbox.svc:3000'},
              {'name': 'CAMERA_ID', 'value': 'camera'}, {'name': 'SPOOL_DIR', 'value': '/spool'}]
    # 旧設定のcamera ID/codecを維持する。RTSP値はSecret参照のみ。
    old_c = next(d for d in legacy if d and d.get('kind') == 'CronJob')['spec']['jobTemplate']['spec']['template']['spec']['containers'][0]
    keep = [e for e in old_c.get('env', []) if e['name'] == 'CAMERA_ID' or e['name'].startswith('FFMPEG_')]
    common = [e for e in common if e['name'] not in {v['name'] for v in keep}] + keep
    recorder['env'] = common + [{'name': 'RTSP_URL', 'valueFrom': {'secretKeyRef': {'name': 'home-camera', 'key': 'RTSP_URL'}}},
                                {'name': 'SEGMENT_SECONDS', 'value': '300'}, {'name': 'SPOOL_MAX_BYTES', 'value': '85899345920'}]
    recorder['volumeMounts'] = [{'name': 'spool', 'mountPath': '/spool'}]
    recorder['ports'] = [{'name': 'metrics', 'containerPort': 9090}]
    recorder['startupProbe'] = {'httpGet': {'path': '/health', 'port': 9090}, 'periodSeconds': 5, 'failureThreshold': 60}
    recorder['livenessProbe'] = {'httpGet': {'path': '/health', 'port': 9090}, 'periodSeconds': 15, 'failureThreshold': 4}
    recorder['resources']['limits'] = {'cpu': '1', 'memory': '512Mi'}
    upload = container('uploader', image('home-camera'), '/usr/local/bin/home-camera', ['--upload'])
    upload['env'] = copy.deepcopy(common)
    upload['volumeMounts'] = [{'name': 'spool', 'mountPath': '/spool'}]
    template = pod('home-camera-recorder', [recorder, upload])
    template['metadata']['labels'].pop(DB_LABEL, None)
    template['spec']['volumes'] = []
    template['metadata']['annotations'] = {'prometheus.io/scrape': 'true', 'prometheus.io/port': '9090', 'prometheus.io/path': '/metrics'}
    template['spec']['terminationGracePeriodSeconds'] = 45
    template['spec']['volumes'].append({'name': 'spool', 'persistentVolumeClaim': {'claimName': 'home-camera-spool'}})
    stateful = {'apiVersion': 'apps/v1', 'kind': 'StatefulSet', 'metadata': {'name': 'home-camera', 'namespace': 'sandbox', 'annotations': {'reloader.stakater.com/auto': 'true'}},
                'spec': {'replicas': 0, 'serviceName': 'home-camera', 'selector': {'matchLabels': {'app': 'home-camera-recorder'}}, 'template': template}}
    pvc = {'apiVersion': 'v1', 'kind': 'PersistentVolumeClaim', 'metadata': {'name': 'home-camera-spool', 'namespace': 'sandbox'},
           'spec': {'accessModes': ['ReadWriteOnce'], 'storageClassName': 'nfs-external', 'resources': {'requests': {'storage': '100Gi'}}}}
    service = {'apiVersion': 'v1', 'kind': 'Service', 'metadata': {'name': 'home-camera', 'namespace': 'sandbox'},
               'spec': {'clusterIP': 'None', 'selector': {'app': 'home-camera-recorder'}, 'ports': [{'name': 'metrics', 'port': 9090}]}}
    emit(args.output, 'home-camera', [*[d for d in legacy if d and d['kind'] == 'CronJob'], pvc, service, stateful])

    access = list(yaml.safe_load_all((ROOT / 'manifests/access/hitomi-upload-viewer/manifest.yaml').read_text()))
    route = next(d for d in access if d['metadata']['name'] == 'hitomi-upload-viewer-internal')
    route['spec']['rules'].insert(0, {'matches': [{'path': {'type': 'PathPrefix', 'value': '/media/'}}],
                                   'backendRefs': [{'name': 'media-api', 'port': 3000}]})
    emit(args.output, 'access', access)
    viewer = load('hitomi-upload-viewer')
    c = next(d for d in viewer if d and d['kind'] == 'Deployment')['spec']['template']['spec']['containers'][0]
    c['image'] = image('hitomi-upload-viewer')
    c['env'].extend([{'name': 'DIRECT_MEDIA_DELIVERY', 'value': 'true'}, {'name': 'MEDIA_CATALOG', 'value': 'true'}])
    emit(args.output, 'hitomi-upload-viewer', viewer)
    print(f'Prepared review manifests in {args.output}; nothing applied')


if __name__ == '__main__':
    main()
