#!/usr/bin/env python3
"""RTSP値を出力せず、既存Git宣言からKubernetes Secretへ一度だけ移す。"""
import argparse
import base64
import json
from pathlib import Path
import subprocess

import yaml

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rtsp-file', type=Path, help='値だけを含む権限0600のファイル。省略時はGit HEADの旧宣言を読む')
    parser.add_argument('--apply', action='store_true', help='省略時はserver dry-runのみ')
    args = parser.parse_args()
    if args.rtsp_file:
        value = args.rtsp_file.read_text().strip()
    else:
        source = subprocess.run(
            ['git', 'show', 'HEAD:manifests/apps/home-camera/manifest.yaml'],
            cwd=ROOT, check=True, capture_output=True, text=True).stdout
        values = []
        for doc in yaml.safe_load_all(source):
            if doc and doc.get('kind') == 'CronJob':
                for container in doc['spec']['jobTemplate']['spec']['template']['spec']['containers']:
                    values.extend(e['value'] for e in container.get('env', [])
                                  if e.get('name') == 'RTSP_URL' and 'value' in e)
        if len(values) != 1:
            raise SystemExit('旧宣言にRTSP_URLが1つありません。--rtsp-fileを指定してください。')
        value = values[0]
    if not value.startswith('rtsp://'):
        raise SystemExit('RTSP_URLの形式が不正です。')
    secret = {'apiVersion': 'v1', 'kind': 'Secret',
              'metadata': {'name': 'home-camera', 'namespace': 'sandbox'},
              'type': 'Opaque', 'data': {'RTSP_URL': base64.b64encode(value.encode()).decode()}}
    command = ['kubectl', 'apply', '--server-side', '--field-manager=camera-bootstrap', '-f', '-', '-o', 'name']
    if not args.apply:
        command.append('--dry-run=server')
    subprocess.run(command, input=json.dumps(secret), text=True, check=True)


if __name__ == '__main__':
    main()
