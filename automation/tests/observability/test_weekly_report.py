import importlib.util
from pathlib import Path
import datetime as dt
import unittest

path = Path(__file__).resolve().parents[3] / 'manifests/platform/observability/scripts/weekly-report.py'
spec = importlib.util.spec_from_file_location('weekly_report', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReportTests(unittest.TestCase):
    def test_missing_is_not_healthy(self):
        self.assertEqual(module.summarize([]), 'データなし')
        self.assertEqual(module.summarize([{'value': [0, '0']}]), '0 / 1 対象')
        self.assertEqual(module.summarize([{'value': [0, '1']}]), '1 / 1 対象')

    def test_partial_failure_and_secret_redaction(self):
        def broken(_):
            raise RuntimeError('https://hooks.slack.com/services/SECRET')
        text, errors = module.report(broken, dt.datetime(2026, 10, 19, tzinfo=dt.timezone.utc))
        self.assertEqual(len(errors), 11)
        self.assertIn('不完全', text)
        self.assertNotIn('SECRET', text)
        self.assertIn('2026-10-19 09:00', text)

    def test_no_restarts_and_positive_ranking(self):
        def fetch(expr):
            if expr == module.PVC_INFO or expr in module.PVC_STATS.values():
                return []
            if expr == module.RESTARTS:
                return [{'metric': {'namespace': 'apps', 'pod': '<pod>', 'container': 'app'}, 'value': [0, '3.2']}]
            return [{'value': [0, '0']}]
        text, errors = module.report(fetch, dt.datetime.now(dt.timezone.utc))
        self.assertFalse(errors)
        self.assertIn('apps/&lt;pod&gt;/app: 約 3.2 回', text)
        self.assertIn('0 / 1 対象', text)

    def test_pvc_capacity_and_missing(self):
        def row(name, value):
            return {'metric': {'namespace': 'apps', 'persistentvolumeclaim': name}, 'value': [0, str(value)]}
        def fetch(expr):
            if expr == module.PVC_INFO:
                return [row('full', 1), row('unknown', 1)]
            kind = next(k for k, v in module.PVC_STATS.items() if v == expr)
            return [row('full', {'available': 5, 'capacity': 100, 'used': 90}[kind] * 2**30)]
        text = '\n'.join(module.pvc_report(fetch))
        self.assertIn('空き 5.0 GiB (5.0%)', text)
        self.assertIn('使用 90.0 GiB (90.0%)', text)
        self.assertIn('apps/unknown: 容量取得不可', text)
        self.assertIn('🔴', text)

    def test_shared_nfs_is_one_line_without_summing(self):
        def row(name, value):
            return {'metric': {'namespace': 'apps', 'persistentvolumeclaim': name,
                               'storageclass': 'nfs-external'}, 'value': [0, str(value)]}
        def fetch(expr):
            if expr == module.PVC_INFO:
                return [row('a', 1), row('b', 1), row('missing', 1)]
            kind = next(k for k, v in module.PVC_STATS.items() if v == expr)
            return [row(name, values[kind] * 2**30) for name, values in
                    [('a', {'available': 40, 'capacity': 100, 'used': 50}),
                     ('b', {'available': 30, 'capacity': 100, 'used': 60})]]
        text = '\n'.join(module.pvc_report(fetch))
        self.assertEqual(text.count('共有 NFS (nfs-external)'), 1)
        self.assertIn('空き 30.0 GiB', text)
        self.assertIn('総容量 100.0 GiB', text)
        self.assertIn('容量取得 2/3 PVC', text)
        self.assertNotIn('apps/', text)
        missing = '\n'.join(module.pvc_report(lambda expr: fetch(expr) if expr == module.PVC_INFO else []))
        self.assertIn('容量取得不可 — 容量取得 0/3 PVC', missing)


if __name__ == '__main__':
    unittest.main()
