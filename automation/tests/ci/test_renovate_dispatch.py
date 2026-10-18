"""PR の所有確認と同一 HEAD の検証重複防止を検証する。"""

import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "dispatch", ROOT / "automation/scripts/ci/dispatch-renovate-validation.py"
)
dispatch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dispatch)


class DispatchTests(unittest.TestCase):
    def test_new_head_and_cancelled_run(self):
        self.assertTrue(dispatch.needs_validation([], "new"))
        self.assertTrue(dispatch.needs_validation([{"head_sha": "old"}], "new"))
        self.assertTrue(dispatch.needs_validation([
            {"head_sha": "new", "conclusion": "cancelled"}
        ], "new"))

    def test_existing_runs_are_not_repeated(self):
        for conclusion in (None, "success", "failure"):
            with self.subTest(conclusion=conclusion):
                self.assertFalse(dispatch.needs_validation([
                    {"head_sha": "new", "conclusion": conclusion}
                ], "new"))

    @patch.dict(os.environ, {"GH_REPO": "owner/repo"})
    def test_only_owned_bot_pr_is_dispatched(self):
        def pr(number, repo="owner/repo", user="github-actions[bot]", ref="renovate/image"):
            return {"number": number, "user": {"login": user}, "head": {
                "ref": ref, "sha": str(number), "repo": {"full_name": repo}
            }}
        pulls = [[pr(1), pr(2, repo="fork/repo"), pr(3, user="other"), pr(4, ref="feature/test")]]
        with patch.object(dispatch, "gh", side_effect=[
            json.dumps(pulls), json.dumps({"workflow_runs": []}), ""
        ]) as gh:
            dispatch.main()
        self.assertEqual(gh.call_count, 3)
        self.assertEqual(gh.call_args.args, (
            "workflow", "run", dispatch.WORKFLOW, "--ref", "renovate/image"
        ))


if __name__ == "__main__":
    unittest.main()
