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


if __name__ == '__main__':
    unittest.main()
