"""Helm values の階層違いによる resources の適用漏れを検出する。"""
from pathlib import Path
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[3]


class PlatformResourcesTests(unittest.TestCase):
    def test_rendered_storage_and_registry_containers_have_resource_budgets(self):
        for app in ('rustfs', 'harbor'):
            rendered = subprocess.check_output(
                ['kustomize', 'build', '--enable-helm', str(ROOT / 'manifests/platform' / app)],
                text=True,
            )
            workloads = [doc for doc in yaml.safe_load_all(rendered)
                         if doc and doc.get('kind') in ('Deployment', 'StatefulSet')]
            self.assertTrue(workloads, f'{app}: workload が展開されていません')
            for workload in workloads:
                for container in workload['spec']['template']['spec']['containers']:
                    with self.subTest(app=app, workload=workload['metadata']['name'],
                                      container=container['name']):
                        resources = container.get('resources') or {}
                        requests = resources.get('requests') or {}
                        limits = resources.get('limits') or {}
                        self.assertIn('cpu', requests, 'CPU request が chart 展開時に失われています')
                        self.assertIn('memory', requests, 'memory request が chart 展開時に失われています')
                        self.assertIn('memory', limits, 'memory limit が chart 展開時に失われています')


if __name__ == '__main__':
    unittest.main()
