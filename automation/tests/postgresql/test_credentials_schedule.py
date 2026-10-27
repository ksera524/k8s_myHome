"""定期実行を間引いても同期時の資格情報・CA 配布を待たせない。"""
from pathlib import Path
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[3]


class CredentialsScheduleTest(unittest.TestCase):
    def test_sync_hook_uses_the_complete_cronjob_template(self):
        rendered = subprocess.check_output(
            ['kustomize', 'build', '--enable-helm',
             str(ROOT / 'manifests/platform/shared-postgresql')],
            text=True,
        )
        objects = {(d['kind'], d['metadata']['name']): d
                   for d in yaml.safe_load_all(rendered) if d}
        cronjob = objects['CronJob', 'postgresql-credentials']
        hook = objects['Job', 'postgresql-credentials-sync']
        self.assertEqual(cronjob['spec']['schedule'], '*/30 * * * *')
        self.assertEqual(cronjob['spec']['concurrencyPolicy'], 'Forbid')
        self.assertEqual(hook['metadata']['annotations']['argocd.argoproj.io/hook'], 'PostSync')
        self.assertEqual(hook['metadata']['annotations']['argocd.argoproj.io/hook-delete-policy'],
                         'BeforeHookCreation,HookSucceeded')
        self.assertEqual(hook['spec'], cronjob['spec']['jobTemplate']['spec'])
        pod = hook['spec']['template']['spec']
        self.assertEqual(pod['serviceAccountName'], 'postgresql-credentials')
        scripts = next(v['configMap']['name'] for v in pod['volumes'] if v['name'] == 'scripts')
        self.assertIn(('ConfigMap', scripts), objects, 'Hook の参照先に生成済み ConfigMap が必要')
        self.assertEqual(pod['containers'][0]['command'], ['python3', '/scripts/reconcile.py'])


if __name__ == '__main__':
    unittest.main()
