#!/usr/bin/env python3
"""PGO chart を正本として関連イメージを同期・検証する。"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[3]
REGISTRY = 'registry.developers.crunchydata.com/crunchydata'
CLIENTS = [
    'manifests/platform/shared-postgresql/credentials.yaml',
    'manifests/platform/harbor/harbor-database-patch.yaml',
    'manifests/platform/harbor/harbor-jobservice-database-patch.yaml',
    'automation/examples/postgresql/restore-test.yaml',
]


def load(path):
    return yaml.safe_load(path.read_text())


def chart_source(root):
    source = load(root / 'manifests/platform/pgo/kustomization.yaml')['helmCharts']
    assert len(source) == 1 and source[0]['name'] == 'pgo', 'PGO chart の定義が不正です'
    assert source[0]['repo'] == f'oci://{REGISTRY}', 'PGO chart の取得元が不正です'
    assert re.fullmatch(r'\d+\.\d+\.\d+', str(source[0]['version'])), 'PGO version が不正です'
    return source[0]


def chart_dir(root):
    return root / 'manifests/platform/pgo/charts' / f"pgo-{chart_source(root)['version']}" / 'pgo'


def fetch_chart(root):
    version = str(chart_source(root)['version'])
    destination = chart_dir(root)
    if destination.exists():
        return
    with tempfile.TemporaryDirectory() as temporary:
        temp = Path(temporary)
        subprocess.run(['helm', 'pull', f'oci://{REGISTRY}/pgo', '--version', version,
                        '--destination', str(temp)], check=True, timeout=180)
        with tarfile.open(temp / f'pgo-{version}.tgz') as archive:
            for item in archive.getmembers():
                parts = Path(item.name).parts
                assert parts and parts[0] == 'pgo' and '..' not in parts, 'chart path が不正です'
                assert item.isdir() or item.isfile(), 'chart のリンク・特殊ファイルは許可しません'
            archive.extractall(temp, filter='data')
        assert str(load(temp / 'pgo/Chart.yaml')['version']) == version, 'chart version 不一致'
        shutil.copytree(temp / 'pgo', destination)


def expected(root):
    chart = chart_dir(root)
    source = chart_source(root)
    metadata = load(chart / 'Chart.yaml')
    assert metadata['name'] == 'pgo' and str(metadata['version']) == str(source['version']), '同梱 chart の版が不一致です'
    values = load(chart / 'values.yaml')
    # ローカル values による controller / relatedImages の差し替えも取りこぼさない。
    overrides = load(root / 'manifests/platform/pgo/values.yaml')
    assert not {'controllerImages', 'relatedImages'} & overrides.keys(), 'イメージの上書きは chart へ統一してください'
    cluster = load(root / 'manifests/platform/shared-postgresql/postgrescluster.yaml')
    major = cluster['spec']['postgresVersion']
    assert isinstance(major, int), 'postgresVersion は整数を指定してください'
    images = values['relatedImages']
    postgres = images[f'postgres_{major}']['image']
    match = re.fullmatch(re.escape(f'{REGISTRY}/crunchy-postgres:ubi9-') + r'(\d+)\.\d+(?:\.\d+)?-\d+', postgres)
    assert match and int(match[1]) == major, 'PostgreSQL メジャー / OS が不一致です'
    operator = values['controllerImages']['cluster']
    assert operator.startswith(f"{REGISTRY}/postgres-operator:ubi9-{source['version']}-"), 'Operator / chart の版が不一致です'
    return postgres, images['pgbackrest']['image']


def image_references(root):
    paths = ['manifests/platform/shared-postgresql/postgrescluster.yaml', *CLIENTS]
    for name in paths:
        path = root / name
        for match in re.finditer(r'(?m)^(\s*image:\s*)(\S+)\s*$', path.read_text()):
            yield path, match[2]


def check(root):
    postgres, backrest = expected(root)
    cluster = load(root / "manifests/platform/shared-postgresql/postgrescluster.yaml")
    assert cluster["spec"]["backups"]["pgbackrest"]["image"] == backrest, "pgBackRest イメージが chart と不一致です"
    found = set()
    for path, image in image_references(root):
        if '/crunchy-postgres:' in image:
            assert image == postgres, f'{path.relative_to(root)}: PostgreSQL イメージが chart と不一致です'
            found.add(path)
        elif '/crunchy-pgbackrest:' in image:
            assert image == backrest, f'{path.relative_to(root)}: pgBackRest イメージが chart と不一致です'
    assert len(found) == len(CLIENTS) + 1, 'PostgreSQL 利用箇所のイメージが不足しています'
    print(f'PGO {chart_source(root)["version"]}: PostgreSQL / pgBackRest / 補助コンテナの整合性 OK')


def sync(root):
    fetch_chart(root)
    postgres, backrest = expected(root)
    paths = {path for path, _ in image_references(root)}
    for path in paths:
        text = re.sub(re.escape(f'{REGISTRY}/crunchy-postgres:') + r'[\w.\-]+', postgres, path.read_text())
        text = re.sub(re.escape(f'{REGISTRY}/crunchy-pgbackrest:') + r'[\w.\-]+', backrest, text)
        path.write_text(text)
    check(root)
    # 新 chart の検証に成功してから旧配布物を取り除く。
    for old in (root / 'manifests/platform/pgo/charts').glob('pgo-*'):
        if old != chart_dir(root).parent:
            shutil.rmtree(old)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--sync', action='store_true')
    args = parser.parse_args()
    (sync if args.sync else check)(args.root.resolve())


if __name__ == '__main__':
    main()
