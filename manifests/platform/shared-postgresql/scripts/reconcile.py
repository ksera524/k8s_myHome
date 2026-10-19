"""ESC の入力資格情報を PGO に反映し、公開 CA だけを Harbor に配布する。"""
import base64
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import urllib.request

API = 'https://kubernetes.default.svc'
SA = Path('/var/run/secrets/kubernetes.io/serviceaccount')
CLUSTER = 'shared-postgresql'
HOST = f'{CLUSTER}-primary.database.svc.cluster.local'


def request(path, method='GET', body=None):
    headers = {'Authorization': 'Bearer ' + (SA / 'token').read_text()}
    if body is not None:
        headers['Content-Type'] = 'application/merge-patch+json' if method == 'PATCH' else 'application/json'
    req = urllib.request.Request(API + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    with urllib.request.urlopen(req, context=ssl.create_default_context(cafile=str(SA / "ca.crt")), timeout=20) as response:
        return json.load(response)


def reconcile_password(user, password):
    path = f'/api/v1/namespaces/database/secrets/{CLUSTER}-pguser-{user}'
    secret = request(path)
    desired = base64.b64encode(password.encode()).decode()
    if secret.get('data', {}).get('password') != desired:
        # resourceVersion により、同時更新された Secret の上書きを避ける。
        request(path, 'PATCH', {'metadata': {'resourceVersion': secret['metadata']['resourceVersion']}, 'data': {'password': desired, 'verifier': None}})
        print(f'{user}: password update requested')
    else:
        print(f'{user}: password unchanged')


def main():
    admin = Path('/input/admin-password').read_text()
    harbor = Path('/input/harbor-password').read_text()
    reconcile_password('postgres', admin)
    reconcile_password('harbor', harbor)
    cert = request(f'/api/v1/namespaces/database/secrets/{CLUSTER}-cluster-cert')
    ca = base64.b64decode(cert['data']['ca.crt']).decode()
    # 公開 CA のみを配布。秘密鍵や管理用資格情報をコピーしない。
    cm_path = '/api/v1/namespaces/harbor/configmaps/shared-postgresql-ca'
    try:
        current = request(cm_path)
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
        request('/api/v1/namespaces/harbor/configmaps', 'POST', {'apiVersion': 'v1', 'kind': 'ConfigMap', 'metadata': {'name': 'shared-postgresql-ca', 'namespace': 'harbor', 'labels': {'app.kubernetes.io/managed-by': 'postgresql-credentials'}}, 'data': {'ca.crt': ca}})
    else:
        if current.get('data', {}).get('ca.crt') != ca:
            request(cm_path, 'PATCH', {'metadata': {'resourceVersion': current['metadata']['resourceVersion']}, 'data': {'ca.crt': ca}})
    with tempfile.NamedTemporaryFile(mode='w') as root:
        root.write(ca)
        root.flush()
        env = {**os.environ, 'PGHOST': HOST, 'PGUSER': 'postgres', 'PGDATABASE': 'postgres', 'PGPASSWORD': admin, 'PGSSLMODE': 'verify-full', 'PGSSLROOTCERT': root.name, 'PGCONNECT_TIMEOUT': '10'}
        # PGO の password 反映前なら失敗し、Job の再試行に委ねる。
        subprocess.run(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-c', 'ALTER DATABASE registry OWNER TO harbor; REVOKE CONNECT, TEMPORARY ON DATABASE registry FROM PUBLIC; GRANT CONNECT ON DATABASE registry TO harbor; REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;'], env=env, check=True, stdout=subprocess.DEVNULL)
        env.update(PGUSER='harbor', PGDATABASE='registry', PGPASSWORD=harbor)
        subprocess.run(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-c', 'SELECT 1'], env=env, check=True, stdout=subprocess.DEVNULL)
    print('Credentials and TLS verified; migration gate is not modified')


if __name__ == '__main__':
    main()
