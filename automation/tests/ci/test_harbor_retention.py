"""保持対象を削除しないこと、世代上限と標準policyの対象範囲を検証する。"""
import importlib.util
import json
import os
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('harbor_retention', ROOT / 'automation/scripts/harbor/retention.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def d(n):
    return 'sha256:' + f'{n:064x}'


def artifacts(count, latest):
    return [{'digest': d(n), 'type': 'IMAGE', 'size': n * 100,
             'tags': [{'name': 'latest'}] if n == latest else []} for n in range(1, count + 1)]


def app(current):
    return {'status': {'health': {'status': 'Healthy'}, 'sync': {'status': 'Synced'},
                       'summary': {'images': ['harbor.qroksera.com/sandbox/api-hub:latest@' + current]}}}


def pod(current, phase='Running'):
    image = 'harbor.qroksera.com/sandbox/api-hub:latest@' + current
    return {'kind': 'Pod', 'spec': {'containers': [{'image': image}]},
            'status': {'phase': phase, 'conditions': [{'type': 'Ready', 'status': 'True'}],
                       'containerStatuses': [{'image': image, 'imageID': image}]}}


class RetentionTests(unittest.TestCase):
    def test_four_releases_preserve_roles_not_three_newest(self):
        # 最新ビルドが増えても稼働版と正常稼働した切り戻し版を残す。
        for candidate in range(4, 9):
            result = MODULE.plan(artifacts(candidate, candidate), d(2), d(1))
            self.assertEqual(result['keep'], [d(1), d(2), d(candidate)])
            self.assertEqual(len(result['delete']), candidate - 3)

    def test_same_digest_counts_once_and_initial_unknown_does_not_invent_previous(self):
        self.assertEqual(MODULE.plan(artifacts(4, 4), d(4), d(4))['keep'], [d(4)])
        self.assertNotIn('previous', MODULE.plan(artifacts(4, 4), d(2), None)['roles'])

    def test_rollback_and_failed_deployment_keep_previous(self):
        result = MODULE.plan(artifacts(5, 5), d(2), d(4))
        self.assertEqual(result['keep'], [d(2), d(4), d(5)])
        failed = app(d(2))
        failed['status']['health']['status'] = 'Degraded'
        with self.assertRaises(ValueError):
            MODULE.observed_current(failed, {'items': [pod(d(2))]}, 'sandbox/api-hub')

    def test_rolling_pods_and_unpinned_images_stop_cleanup(self):
        for workloads in ([pod(d(2)), pod(d(1))], []):
            with self.subTest(workloads=workloads), self.assertRaises(ValueError):
                MODULE.observed_current(app(d(2)), {'items': workloads}, 'sandbox/api-hub')
        with self.assertRaises(ValueError):
            MODULE.image_digest('harbor.qroksera.com/sandbox/api-hub:latest', 'sandbox/api-hub')

    def test_terminal_pods_ignored_but_pending_old_pods_protected(self):
        self.assertEqual(MODULE.observed_current(app(d(2)),
                         {'items': [pod(d(2)), pod(d(1), 'Succeeded')]}, 'sandbox/api-hub'), d(2))
        with self.assertRaises(ValueError):
            MODULE.observed_current(app(d(2)), {'items': [pod(d(2)), pod(d(1), 'Pending')]}, 'sandbox/api-hub')

    def test_actual_image_id_mismatch_stops(self):
        running = pod(d(2))
        running['status']['containerStatuses'][0]['imageID'] = 'docker-pullable://repo@' + d(1)
        with self.assertRaises(ValueError):
            MODULE.observed_current(app(d(2)), {'items': [running]}, 'sandbox/api-hub')

    def test_missing_latest_previous_and_indexes_stop(self):
        cases = [(artifacts(4, 0), d(2), None), (artifacts(4, 4), d(2), d(9))]
        index = artifacts(4, 4)
        index[0]['references'] = [{'child_digest': d(8)}]
        cases.append((index, d(2), d(1)))
        for args in cases:
            with self.subTest(args=args), self.assertRaises(ValueError):
                MODULE.plan(*args)

    def test_policy_keeps_other_repos_and_only_selected_pilot_digests(self):
        result = MODULE.policy(1, 'api-hub', [d(1), d(2), d(3)])
        self.assertEqual(result['trigger']['kind'], '')
        self.assertEqual(result['algorithm'], 'or')
        targeted, other = result['rules']
        self.assertEqual(targeted['template'], 'always')
        self.assertEqual(targeted['scope_selectors']['repository'][0],
                         {'kind': 'doublestar', 'decoration': 'repoMatches', 'pattern': 'api-hub'})
        self.assertFalse(json.loads(targeted['tag_selectors'][0]['extras'])['untagged'])
        self.assertEqual(other['scope_selectors']['repository'][0]['decoration'], 'repoExcludes')
        self.assertEqual(other['tag_selectors'][0]['pattern'], '**')
        self.assertTrue(json.loads(other['tag_selectors'][0]['extras'])['untagged'])
        self.assertEqual(targeted['tag_selectors'][0]['pattern'].count('retain-'), 3)

    def test_project_quota_caps_unlimited_and_preserves_stricter_limit(self):
        quota = {'used': {'storage': 900}, 'hard': {'storage': -1}}
        self.assertEqual(MODULE.quota_limit(quota, 4096), 4096)
        quota['hard']['storage'] = 2048
        self.assertEqual(MODULE.quota_limit(quota, 4096), 2048)
        with self.assertRaises(ValueError):
            MODULE.quota_limit(quota, 800)

    def test_manual_policy_server_generated_fields_do_not_change_semantics(self):
        expected = MODULE.policy(2, 'api-hub', [d(1)])
        actual = json.loads(json.dumps(expected))
        actual['id'] = 7
        actual['rules'][0]['id'] = 8
        actual['trigger']['references'] = {'job_id': 9}
        # Harbor実APIはGoのomitemptyによりゼロ値を省略する。
        for rule in actual['rules']:
            for key in ('priority', 'disabled', 'params'):
                rule.pop(key)
        self.assertEqual(MODULE.canonical(actual), MODULE.canonical(expected))
        actual['rules'][0]['disabled'] = True
        self.assertNotEqual(MODULE.canonical(actual), MODULE.canonical(expected))

    def test_harbor_pagination_reads_more_than_first_page(self):
        client = MODULE.Harbor('https://example.invalid', 'robot', 'secret')
        with patch.object(client, 'request', side_effect=[list(range(100)), [101]]) as request:
            self.assertEqual(len(client.pages('/artifacts?with_tag=true')), 101)
            self.assertIn('&page=2', request.call_args.args[1])

    def test_cli_default_is_read_only_and_changed_review_stops_writes(self):
        selected = MODULE.plan(artifacts(4, 4), d(2), d(1))
        quota = {'id': 2, 'used': {'storage': 1000}, 'hard': {'storage': -1}}
        project = {'project_id': 2, 'metadata': {}}
        client = MODULE.Harbor('https://example.invalid', 'robot', 'secret')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            password = root / 'password'
            password.write_text('secret')
            argv = ['retention.py', '--previous', d(1), '--output', str(root / 'plan.json')]
            with patch.dict(os.environ, {'HARBOR_PASSWORD_FILE': str(password)}), \
                 patch.object(MODULE, 'Harbor', return_value=client), \
                 patch.object(MODULE, 'snapshot', return_value=selected), \
                 patch.object(client, 'request', return_value=project) as request, \
                 patch.object(client, 'pages', return_value=[quota]), \
                 patch('sys.argv', argv), patch('builtins.print'):
                MODULE.main()
                self.assertTrue(all(c.args[0] == 'GET' for c in request.call_args_list))
                request.reset_mock()
                reviewed = json.loads((root / 'plan.json').read_text())
                reviewed['keep'] = [d(9)]
                (root / 'reviewed.json').write_text(json.dumps(reviewed))
                argv[argv.index(str(root / 'plan.json'))] = str(root / 'apply.json')
                argv += ['--apply', '--maintenance', '--reviewed-plan', str(root / 'reviewed.json')]
                with self.assertRaises(ValueError):
                    MODULE.main()
                self.assertTrue(all(c.args[0] == 'GET' for c in request.call_args_list))

    def test_cli_apply_needs_explicit_maintenance_and_review(self):
        with patch('sys.argv', ['retention.py', '--no-previous-known', '--output', '/unused', '--apply']), \
             patch.object(MODULE, 'Harbor') as client, patch('sys.stderr'):
            with self.assertRaises(SystemExit):
                MODULE.main()
            client.assert_not_called()

    def test_failed_retention_does_not_report_success(self):
        client = MODULE.Harbor('https://example.invalid', 'robot', 'secret')
        with patch.object(client, 'pages', return_value=[{'id': 1, 'dry_run': True, 'status': 'Error'}]):
            with self.assertRaises(RuntimeError):
                MODULE.wait_execution(client, 1, set(), True)


if __name__ == '__main__':
    unittest.main()
