"""PR の所有境界と、同期失敗時の後片付けを検証する。"""
import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('syncer', ROOT / 'automation/scripts/ci/sync-renovate-postgresql.py')
SYNCER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNCER)


def pr(repo='owner/repo', user='github-actions[bot]', ref='renovate/postgresql'):
    return {'number': 1, 'user': {'login': user}, 'head': {'sha': 'a' * 40, 'ref': ref, 'repo': {'full_name': repo}}}


@patch.dict(os.environ, {'GH_REPO': 'owner/repo'})
class RenovateSyncTest(unittest.TestCase):
    def test_foreign_prs_do_not_fetch_or_run_code(self):
        pulls = [[pr(repo='fork/repo'), pr(user='someone'), pr(ref='feature/test')]]
        with patch.object(SYNCER, 'run', return_value=json.dumps(pulls)) as run:
            SYNCER.main()
        self.assertEqual(run.call_count, 1)

    def test_other_renovate_prs_are_not_changed(self):
        with patch.object(SYNCER, 'run', side_effect=[json.dumps([[pr()]]), json.dumps([[{'filename': 'renovate.json'}]])]) as run:
            SYNCER.main()
        self.assertEqual(run.call_count, 2)

    def test_sync_failure_removes_worktree_without_commit_or_push(self):
        files = [[{'filename': 'manifests/platform/pgo/kustomization.yaml'}]]
        with patch.object(SYNCER, 'run', side_effect=[json.dumps([[pr()]]), json.dumps(files), '', '', '']) as run:
            with patch.object(SYNCER.VERSIONS, 'sync', side_effect=ValueError('bad chart')):
                with self.assertRaisesRegex(ValueError, 'bad chart'):
                    SYNCER.main()
        self.assertEqual(run.call_args.args[:4], ('git', 'worktree', 'remove', '--force'))
        self.assertFalse(any('push' in call.args or 'commit' in call.args for call in run.call_args_list))


if __name__ == '__main__':
    unittest.main()
