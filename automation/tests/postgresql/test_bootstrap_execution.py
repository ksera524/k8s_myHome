"""実際のpsqlで退役DBの有無、再実行、SQLエラーによる停止を確認する。"""
import getpass
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from test_credentials import MODULE


@unittest.skipUnless(all(shutil.which(tool) for tool in ('initdb', 'pg_ctl', 'psql')),
                     'requires PostgreSQL binaries (initdb, pg_ctl, psql on PATH)')
class BootstrapExecutionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='pg-bootstrap-')
        cls.root = Path(cls.tmp.name)
        cls.env = {**os.environ, 'PGHOST': str(cls.root), 'PGPORT': '55432',
                   'PGUSER': getpass.getuser(), 'PGDATABASE': 'postgres',
                   'PGSSLMODE': 'disable', 'PGPASSWORD': ''}
        subprocess.run(['initdb', '-D', str(cls.root / 'data'), '-A', 'trust', '--no-locale'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            subprocess.run(['pg_ctl', '-D', str(cls.root / 'data'), '-l', str(cls.root / 'log'),
                            '-o', f"-k {cls.root} -h '' -p 55432", '-w', 'start'],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            cls.sql('CREATE ROLE app LOGIN')
            for name in ('registry', 'api_hub', 'hitomi', 'media'):
                cls.sql(f'CREATE DATABASE {name}')
        except Exception:
            cls.tearDownClass()
            raise

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['pg_ctl', '-D', str(cls.root / 'data'), '-m', 'immediate', '-w', 'stop'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        cls.tmp.cleanup()

    @classmethod
    def sql(cls, sql, database='postgres'):
        return subprocess.check_output(['psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-c', sql],
                                       env={**cls.env, 'PGDATABASE': database}, text=True).strip()

    def test_bootstrap_with_and_without_retired_camera_database(self):
        for camera in (False, True):
            with self.subTest(camera=camera):
                if camera:
                    self.sql('CREATE DATABASE camera')
                    self.sql('CREATE TABLE retained_history AS SELECT 42 AS id', 'camera')
                for _ in range(2):
                    MODULE.bootstrap(self.env)
                names = ['registry', 'api_hub', 'hitomi', 'media'] + (['camera'] if camera else [])
                for name in names:
                    self.assertEqual(self.sql(f"SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='{name}'"), 'app')
                    self.assertEqual(self.sql(f"SELECT has_database_privilege('app','{name}','CONNECT')"), 't')
                    self.assertEqual(self.sql(f"SELECT count(*) FROM pg_database d, LATERAL aclexplode(d.datacl) acl WHERE datname='{name}' AND acl.grantee=0 AND acl.privilege_type IN ('CONNECT','TEMPORARY')"), '0')
                if camera:
                    self.assertEqual(self.sql('SELECT id FROM retained_history', 'camera'), '42')
                else:
                    self.assertEqual(self.sql("SELECT count(*) FROM pg_database WHERE datname='camera'"), '0')

    def test_sql_error_stops_before_later_statements(self):
        script = self.root / 'bootstrap.sql'
        script.write_text('SELECT 1 / 0;\nCREATE TABLE must_not_exist(id int);\n')
        with patch.object(MODULE, '__file__', str(self.root / 'reconcile.py')):
            with self.assertRaises(subprocess.CalledProcessError):
                MODULE.bootstrap(self.env)
        self.assertEqual(self.sql("SELECT to_regclass('must_not_exist') IS NULL"), 't')
