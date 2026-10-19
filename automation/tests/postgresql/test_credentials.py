"""PGO 資格情報反映の再実行性と競合防止を検証する。"""
import base64
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[3] / 'manifests/platform/shared-postgresql/scripts/reconcile.py'
SPEC = importlib.util.spec_from_file_location('credentials', PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CredentialsTest(unittest.TestCase):
    def test_same_password_preserves_verifier(self):
        value = base64.b64encode(b'example').decode()
        with patch.object(MODULE, 'request', return_value={'metadata': {'resourceVersion': '5'}, 'data': {'password': value, 'verifier': 'keep'}}) as api:
            MODULE.reconcile_password('harbor', 'example')
        self.assertEqual(api.call_count, 1)

    def test_changed_password_clears_verifier_with_version_guard(self):
        with patch.object(MODULE, 'request', return_value={'metadata': {'resourceVersion': '5'}, 'data': {'password': 'old', 'verifier': 'old', 'uri': 'keep'}}) as api:
            MODULE.reconcile_password('harbor', 'new')
        self.assertEqual(api.call_count, 2)
        body = api.call_args.args[2]
        self.assertEqual(body['metadata'], {'resourceVersion': '5'})
        self.assertEqual(body['data'], {'password': base64.b64encode(b'new').decode(), 'verifier': None})
        self.assertNotIn('uri', body['data'])


if __name__ == '__main__':
    unittest.main()
