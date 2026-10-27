#!/usr/bin/env python3
"""一時 kind で Selenium sidecar の起動順・ブラウザ操作・終了を検証する。"""
import copy
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time

import yaml

ROOT = Path(__file__).resolve().parents[3]
CLIENT_IMAGE = 'python:3.15.0-slim-bookworm'
CLIENT = '''
import base64, json, os, urllib.request
base = os.environ['SELENIUM_COMMAND_EXECUTOR']
def request(method, path, data=None):
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=body, method=method,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)['value']
# retry なしで接続する。startupProbe が先に準備完了を確認する必要がある。
assert request('GET', '/status')['ready'] is True
session = request('POST', '/session', {'capabilities': {'alwaysMatch': {
    'browserName': 'chrome', 'goog:chromeOptions': {'args': [
        '--headless', '--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage',
        '--window-size=1920x1080']}}}})['sessionId']
try:
    request('POST', '/session/' + session + '/url',
            {'url': 'data:text/html,<title>sidecar-ok</title><h1>fixture</h1>'})
    assert request('GET', '/session/' + session + '/title') == 'sidecar-ok'
    screenshot = request('GET', '/session/' + session + '/screenshot')
    assert base64.b64decode(screenshot).startswith(b'\\x89PNG')
finally:
    request('DELETE', '/session/' + session)
print('PASS: startup gate, Chrome session, navigation, screenshot, close', flush=True)
raise SystemExit(int(os.environ['TEST_EXIT_CODE']))
'''


def run(*args, env=None, data=None, timeout=600):
    return subprocess.check_output(args, input=data, text=True, env=env, timeout=timeout)


def main():
    rendered = run('kustomize', 'build', str(ROOT / 'manifests/apps/hitomi'))
    cron = next(d for d in yaml.safe_load_all(rendered) if d['kind'] == 'CronJob')
    original = cron['spec']['jobTemplate']['spec']['template']['spec']
    browser = next(c for c in original['initContainers'] if c['name'] == 'selenium')
    endpoint = next(e for e in original['containers'][0]['env'] if e['name'] == 'SELENIUM_COMMAND_EXECUTOR')
    assert browser['restartPolicy'] == 'Always'
    name = 'selenium-test-' + secrets.token_hex(3)
    with tempfile.TemporaryDirectory(prefix=name) as directory:
        # kind と kubectl の両方で専用設定を使い、本番 context を参照・変更しない。
        env = {**os.environ, 'KUBECONFIG': str(Path(directory) / 'kubeconfig')}
        def kubectl(*args, data=None):
            return run('kubectl', '--context', 'kind-' + name, '--request-timeout=30s',
                       *args, env=env, data=data)
        try:
            run('kind', 'create', 'cluster', '--name', name, '--kubeconfig', env['KUBECONFIG'],
                '--wait', '120s', env=env)
            print(kubectl('get', 'nodes', '-o', 'wide'), flush=True)
            for image in [browser['image'], CLIENT_IMAGE]:
                # Docker の multi-platform image export に依存せず、ノードで取得する。
                run('docker', 'exec', name + '-control-plane', 'crictl', 'pull', image)
            for case, exit_code in [('success', 0), ('failure', 7), ('startup-blocked', 0)]:
                spec = copy.deepcopy(original)
                # 本番の資格情報・DB・外部サイトを使わず、同じ sidecar と接続先を検証する。
                spec.pop('imagePullSecrets', None)
                spec['automountServiceAccountToken'] = False
                spec['volumes'] = [v for v in spec['volumes'] if v['name'] == 'selenium-shm']
                spec['containers'] = [{'name': 'client', 'image': CLIENT_IMAGE,
                                       'command': ['python3', '-c', CLIENT],
                                       'env': [endpoint, {'name': 'TEST_EXIT_CODE', 'value': str(exit_code)}]}]
                if case == 'startup-blocked':
                    spec['initContainers'][0]['startupProbe']['exec']['command'] = ['sh', '-c', 'exit 1']
                job = {'apiVersion': 'batch/v1', 'kind': 'Job', 'metadata': {'name': case},
                       'spec': {'backoffLimit': 0, 'activeDeadlineSeconds': 45 if case == 'startup-blocked' else 300,
                                'template': {'spec': spec}}}
                kubectl('create', '-f', '-', data=json.dumps(job))
                deadline = time.monotonic() + 360
                observed_sidecar_id = None
                while time.monotonic() < deadline:
                    pods = json.loads(kubectl('get', 'pods', '-l', 'job-name=' + case, '-o', 'json'))['items']
                    for pod in pods:
                        for status in pod['status'].get('initContainerStatuses', []):
                            if status['name'] == 'selenium' and status.get('containerID'):
                                observed_sidecar_id = status['containerID'].split('://', 1)[1]
                        if case == 'startup-blocked':
                            assert not any(s.get('containerID') for s in pod['status'].get('containerStatuses', [])), pod
                    current = json.loads(kubectl('get', 'job', case, '-o', 'json'))
                    terminal = [c for c in current.get('status', {}).get('conditions', [])
                                if c['type'] in ['Complete', 'Failed'] and c['status'] == 'True']
                    if terminal:
                        break
                    time.sleep(3)
                else:
                    raise TimeoutError(case)
                if case == 'startup-blocked':
                    assert terminal[0]['reason'] == 'DeadlineExceeded', terminal
                    # deadline では controller が Pod 自体を削除する。CRI でも停止を確認する。
                    assert observed_sidecar_id, 'Selenium が起動したことを確認できない'
                    running = run('docker', 'exec', name + '-control-plane', 'crictl', 'ps',
                                  '--id', observed_sidecar_id, '-q').strip()
                    assert not running, running
                else:
                    pod = json.loads(kubectl('get', 'pods', '-l', 'job-name=' + case, '-o', 'json'))['items'][0]
                    sidecar = next(s for s in pod['status']['initContainerStatuses'] if s['name'] == 'selenium')
                    assert 'terminated' in sidecar['state'], (case, sidecar)
                    client = pod['status']['containerStatuses'][0]
                    assert client['state']['terminated']['exitCode'] == exit_code, client
                    assert terminal[0]['type'] == ('Complete' if exit_code == 0 else 'Failed'), terminal
                    print(kubectl('logs', pod['metadata']['name'], '-c', 'client'), flush=True)
                print(f'PASS: {case}; Selenium terminated; Job {terminal[0]["type"]}', flush=True)
        except Exception:
            # テスト Pod だけの診断情報。資格情報や本番データは含まない。
            try:
                print(kubectl('get', 'pods', '-o', 'json'), flush=True)
                print(kubectl('get', 'events', '--sort-by=.metadata.creationTimestamp'), flush=True)
            except subprocess.CalledProcessError:
                pass
            raise
        finally:
            run('kind', 'delete', 'cluster', '--name', name, env=env)


if __name__ == '__main__':
    main()
