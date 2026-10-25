"""共用appを維持したDB追加と資格情報配布の境界を確認する。"""
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[3]


class ApplicationDatabaseTest(unittest.TestCase):
    def test_new_databases_reuse_app_and_revoke_public_connect(self):
        cluster = yaml.safe_load((ROOT / 'manifests/platform/shared-postgresql/postgrescluster.yaml').read_text())
        app = next(user for user in cluster['spec']['users'] if user['name'] == 'app')
        self.assertEqual(set(app['databases']), {'registry', 'api_hub', 'hitomi', 'media'})
        for option in ['NOSUPERUSER', 'NOCREATEDB', 'NOCREATEROLE', 'CONNECTION LIMIT 80']:
            self.assertIn(option, app['options'])
        sql = (ROOT / 'manifests/platform/shared-postgresql/scripts/bootstrap.sql').read_text()
        for database in app['databases']:
            self.assertIn(f'REVOKE CONNECT, TEMPORARY ON DATABASE {database} FROM PUBLIC;', sql)
            self.assertIn(f'ALTER DATABASE {database} OWNER TO app;', sql)

    def test_namespace_copy_uses_existing_password(self):
        secret = yaml.safe_load((ROOT / 'manifests/platform/secrets/external-secrets/postgresql/application-database.yaml').read_text())
        self.assertEqual(secret['metadata']['namespace'], 'sandbox')
        self.assertEqual(secret['spec']['data'], [{'secretKey': 'PGPASSWORD', 'remoteRef': {'key': 'postgresql.password'}}])
