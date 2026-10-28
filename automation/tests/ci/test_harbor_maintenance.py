"""保持と配布の状態遷移・実Pod照合の回帰テスト。"""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('maintenance', ROOT / 'manifests/platform/harbor/scripts/maintenance.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


def digest(n):
    return 'sha256:' + str(n) * 64


def fixture(index=False):
    d = digest(1)
    image = 'harbor.qroksera.com/sandbox/test@' + d
    app = {'status': {'sync': {'status': 'Synced'}, 'health': {'status': 'Healthy'}}}
    pod = {'containers': [{'name': 'app', 'image': image}]}
    items = [{'kind': 'Deployment', 'metadata': {'generation': 1}, 'spec': {'replicas': 1, 'template': {'spec': pod}},
              'status': {'observedGeneration': 1, 'replicas': 1, 'readyReplicas': 1, 'updatedReplicas': 1}},
             {'kind': 'Pod', 'metadata': {}, 'spec': pod,
              'status': {'phase': 'Running', 'conditions': [{'type': 'Ready', 'status': 'True'}],
                         'containerStatuses': [{'name': 'app', 'imageID': 'docker-pullable://test@' + (digest(2) if index else d)}]}}]
    artifacts = [{'digest': d, 'references': [{'child_digest': digest(2)}] if index else []}]
    return app, items, 'sandbox/test', artifacts


class MaintenanceTests(unittest.TestCase):
    def test_four_releases_keep_previous_healthy(self):
        roles = {'latest': digest(1)}
        for n in range(1, 5):
            roles.update(m.transitions(roles, digest(n)))
            self.assertEqual(roles['retain-current'], digest(n))
            if n > 1:
                self.assertEqual(roles['retain-previous'], digest(n-1))
            if n < 4:
                roles['latest'] = digest(n+1)
                roles.update(m.transitions(roles, digest(n)))
                self.assertEqual(roles['deploy'], digest(n+1))
            self.assertLessEqual(len(set(roles.values())), 3)

    def test_pending_deploy_not_overtaken_by_new_latest(self):
        roles = {'retain-current': digest(1), 'deploy': digest(2), 'latest': digest(3)}
        self.assertEqual(m.transitions(roles, digest(1)), [])

    def test_rollback_is_held_despite_bad_latest(self):
        roles = {'retain-previous': digest(1), 'retain-current': digest(2), 'deploy': digest(3), 'latest': digest(3)}
        roles.update(m.transitions(roles, digest(2), digest(1)))
        self.assertEqual(roles['deploy'], digest(1))
        roles.update(m.transitions(roles, digest(1), digest(1)))
        self.assertEqual(roles['retain-previous'], digest(2))
        self.assertEqual(roles['deploy'], digest(1))

    def test_crash_after_previous_and_during_current_tag_move(self):
        roles = {'retain-current': digest(1), 'deploy': digest(2), 'latest': digest(2)}
        changes = m.transitions(roles, digest(2))
        self.assertEqual(changes[:2], [('retain-previous', digest(1)), ('retain-current', digest(2))])
        roles.update(changes[:1])
        del roles['retain-current']
        roles.update(m.transitions(roles, digest(2), seed_previous=digest(3)))
        self.assertEqual(roles['retain-previous'], digest(1))
        self.assertEqual(roles['retain-current'], digest(2))

    def test_plain_manifest_and_oci_index(self):
        for index in (False, True):
            self.assertEqual(m.observe(*fixture(index)), digest(1))

    def test_failed_rollout_and_stale_controller_are_rejected(self):
        for mutation in ('app', 'pod', 'controller', 'image'):
            args = fixture()
            if mutation == 'app': args[0]['status']['health']['status'] = 'Degraded'
            if mutation == 'pod': args[1][1]['status']['conditions'][0]['status'] = 'False'
            if mutation == 'controller': args[1][0]['status']['observedGeneration'] = 0
            if mutation == 'image': args[1][1]['status']['containerStatuses'][0]['imageID'] = digest(3)
            with self.assertRaises(ValueError, msg=mutation): m.observe(*args)

    def test_active_old_job_blocks_but_completed_job_does_not(self):
        args = fixture()
        old = copy.deepcopy(args[1][0])
        old['kind'] = 'Job'
        old['spec']['template']['spec']['containers'][0]['image'] = 'harbor.qroksera.com/sandbox/test@' + digest(2)
        old['status'] = {}
        args[1].append(old)
        args[3].append({'digest': digest(2)})
        with self.assertRaises(ValueError): m.observe(*args)
        old['status']['conditions'] = [{'type': 'Complete', 'status': 'True'}]
        self.assertEqual(m.observe(*args), digest(1))

    def test_unknown_repos_and_untagged_are_preserved_only_in_fallback(self):
        import json
        p = m.retention_policy(2, ['a', 'b'])
        self.assertEqual(p['trigger'], {'kind': ''})
        self.assertFalse(json.loads(p['rules'][0]['tag_selectors'][0]['extras'])['untagged'])
        self.assertEqual(p['rules'][1]['params'], {'latestPushedK': 1})
        self.assertEqual(p['rules'][2]['scope_selectors']['repository'][0]['decoration'], 'repoExcludes')
        self.assertTrue(json.loads(p['rules'][2]['tag_selectors'][0]['extras'])['untagged'])
        self.assertEqual(m.retention_policy(2, [])['rules'][0]['tag_selectors'][0]['pattern'], '**')

class ExclusionTests(unittest.TestCase):
    def test_archive_is_bounded_and_not_in_fallback(self):
        p = m.retention_policy(2, ['active'], ['archive'])
        self.assertEqual(p['rules'][-1]['params'], {'latestPushedK': 3})
        self.assertEqual(p['rules'][-2]['scope_selectors']['repository'][0]['pattern'], '{active,archive}')

    def test_unpinned_template_and_missing_pod_are_rejected(self):
        args = fixture()
        args[1][0]['spec']['template']['spec']['containers'][0]['image'] = 'harbor.qroksera.com/sandbox/test:latest'
        with self.assertRaises(ValueError): m.observe(*args)
        args = fixture()
        args[1].pop()
        with self.assertRaises(ValueError): m.observe(*args)

    def test_lease_contention_prevents_work(self):
        from datetime import datetime, timezone
        class Kube:
            def request(self, method, path, payload=None):
                if method != 'GET': raise AssertionError('must not mutate contended Lease')
                return {'spec': {'holderIdentity': 'other', 'renewTime': datetime.now(timezone.utc).isoformat(),
                                 'leaseDurationSeconds': 1000}}
        with self.assertRaises(RuntimeError):
            with m.lock(Kube()):
                self.fail('must not enter protected section')


if __name__ == '__main__':
    unittest.main()
