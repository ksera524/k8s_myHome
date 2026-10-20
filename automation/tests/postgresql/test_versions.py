"""更新漏れの拒否と chart を正本にした一括同期を検証する。"""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('versions', ROOT / 'automation/scripts/ci/postgresql-versions.py')
VERSIONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERSIONS)


class VersionsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        names = [*VERSIONS.CLIENTS, 'manifests/platform/shared-postgresql/postgrescluster.yaml',
                 'manifests/platform/pgo/kustomization.yaml', 'manifests/platform/pgo/values.yaml']
        for name in names:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        shutil.copytree(VERSIONS.chart_dir(ROOT), VERSIONS.chart_dir(self.root))

    def test_current_and_idempotent_sync(self):
        before = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        VERSIONS.check(self.root)
        VERSIONS.sync(self.root)
        after = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def test_client_image_drift_is_rejected(self):
        path = self.root / VERSIONS.CLIENTS[0]
        current, _ = VERSIONS.expected(self.root)
        path.write_text(path.read_text().replace(current, current.split(':')[0] + ':ubi9-0.0-0'))
        with self.assertRaisesRegex(AssertionError, 'イメージが chart と不一致'):
            VERSIONS.check(self.root)

    def test_missing_chart_and_major_mismatch_are_rejected(self):
        chart = VERSIONS.chart_dir(self.root)
        values = chart / 'values.yaml'
        current, _ = VERSIONS.expected(self.root)
        values.write_text(values.read_text().replace(current, current.split(':')[0] + ':ubi9-999.1-9999'))
        with self.assertRaisesRegex(AssertionError, 'メジャー / OS'):
            VERSIONS.check(self.root)
        shutil.rmtree(chart)
        with self.assertRaises(FileNotFoundError):
            VERSIONS.check(self.root)

    def test_chart_upgrade_updates_every_client_and_backup(self):
        old = VERSIONS.chart_dir(self.root)
        old_version = str(VERSIONS.chart_source(self.root)['version'])
        parts = old_version.split('.')
        parts[-1] = str(int(parts[-1]) + 1)
        new_version = '.'.join(parts)
        new = old.parent.parent / f'pgo-{new_version}/pgo'
        current_pg, current_backup = VERSIONS.expected(self.root)
        major = VERSIONS.load(self.root / 'manifests/platform/shared-postgresql/postgrescluster.yaml')['spec']['postgresVersion']
        next_pg = current_pg.split(':')[0] + f':ubi9-{major}.999-9999'
        next_backup = current_backup.split(':')[0] + ':ubi9-2.999.0-9999'
        shutil.copytree(old, new)
        source = self.root / 'manifests/platform/pgo/kustomization.yaml'
        source.write_text(source.read_text().replace(f'version: {old_version}', f'version: {new_version}'))
        metadata = new / 'Chart.yaml'
        data = yaml.safe_load(metadata.read_text())
        data['version'] = new_version
        metadata.write_text(yaml.safe_dump(data))
        values = new / 'values.yaml'
        values.write_text(values.read_text().replace(f'ubi9-{old_version}-', f'ubi9-{new_version}-')
                          .replace(current_pg, next_pg).replace(current_backup, next_backup))
        VERSIONS.sync(self.root)
        self.assertFalse(old.exists())
        for path, image in VERSIONS.image_references(self.root):
            self.assertIn(image, (next_pg, next_backup), path)

    def test_image_overrides_are_rejected(self):
        path = self.root / 'manifests/platform/pgo/values.yaml'
        data = yaml.safe_load(path.read_text())
        data['relatedImages'] = {}
        path.write_text(yaml.safe_dump(data))
        with self.assertRaisesRegex(AssertionError, '上書き'):
            VERSIONS.check(self.root)


if __name__ == '__main__':
    unittest.main()
