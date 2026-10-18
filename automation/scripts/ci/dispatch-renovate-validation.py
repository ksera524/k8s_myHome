#!/usr/bin/env python3
"""GITHUB_TOKEN で更新した Renovate PR の HEAD に検証を起動する。"""

import json
import os
import subprocess


WORKFLOW = "ci-deploy-validate.yml"


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True)


def needs_validation(runs, sha):
    # 同じ HEAD の完了・実行中・待機中 run があれば重複起動しない。
    # キャンセルされた run は次回に再検証する。
    return not any(
        run["head_sha"] == sha and run.get("conclusion") != "cancelled"
        for run in runs
    )


def main():
    repo = os.environ["GH_REPO"]
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{repo}/pulls?state=open&per_page=100"))
    for pr in (pr for page in pages for pr in page):
        head = pr["head"]
        if (
            not head["ref"].startswith("renovate/")
            or (head.get("repo") or {}).get("full_name") != repo
            or pr["user"]["login"] != "github-actions[bot]"
        ):
            continue
        runs = json.loads(gh(
            "api", "--method", "GET", f"repos/{repo}/actions/workflows/{WORKFLOW}/runs",
            "-f", f"head_sha={head['sha']}", "-f", "per_page=100",
        ))["workflow_runs"]
        if needs_validation(runs, head["sha"]):
            gh("workflow", "run", WORKFLOW, "--ref", head["ref"])
            print(f"検証を起動: PR #{pr['number']} ({head['sha'][:12]})")


if __name__ == "__main__":
    main()
