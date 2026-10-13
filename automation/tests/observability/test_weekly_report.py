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
        self.assertEqual(len(errors), 10)
        self.assertIn('不完全', text)
        self.assertNotIn('SECRET', text)
        self.assertIn('2026-10-19 09:00', text)

    def test_no_restarts_and_positive_ranking(self):
        def fetch(expr):
            if expr == module.RESTARTS:
                return [{'metric': {'namespace': 'apps', 'pod': '<pod>', 'container': 'app'}, 'value': [0, '3.2']}]
            return [{'value': [0, '0']}]
        text, errors = module.report(fetch, dt.datetime.now(dt.timezone.utc))
        self.assertFalse(errors)
        self.assertIn('apps/&lt;pod&gt;/app: 約 3.2 回', text)
        self.assertIn('0 / 1 対象', text)


if __name__ == '__main__':
    unittest.main()
