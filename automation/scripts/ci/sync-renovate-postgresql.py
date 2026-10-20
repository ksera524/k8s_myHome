#!/usr/bin/env python3
"""同一リポジトリの Renovate PR を、信頼済みスクリプトで同期する。"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('versions', ROOT / 'automation/scripts/ci/postgresql-versions.py')
VERSIONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERSIONS)
PATHS = ['manifests/platform/pgo/charts', 'manifests/platform/shared-postgresql',
         'manifests/platform/harbor/harbor-database-patch.yaml',
         'manifests/platform/harbor/harbor-jobservice-database-patch.yaml',
         'automation/examples/postgresql/restore-test.yaml']


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs)


def main():
    repo = os.environ['GH_REPO']
    pages = json.loads(run('gh', 'api', '--paginate', '--slurp', f'repos/{repo}/pulls?state=open&per_page=100'))
    for pr in (pr for page in pages for pr in page):
        head = pr['head']
        if (pr['user']['login'] != 'github-actions[bot]' or
                (head.get('repo') or {}).get('full_name') != repo or
                not head['ref'].startswith('renovate/')):
            continue
        files = json.loads(run('gh', 'api', '--paginate', '--slurp', f'repos/{repo}/pulls/{pr["number"]}/files?per_page=100'))
        if not any(f['filename'] == 'manifests/platform/pgo/kustomization.yaml' for page in files for f in page):
            continue
        run('git', 'fetch', '--no-tags', 'origin', head['sha'], cwd=ROOT)
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary) / 'candidate'
            run('git', 'worktree', 'add', '--detach', str(work), head['sha'], cwd=ROOT)
            try:
                # PR 側のコードや hooks は実行せず、main の同期処理だけで候補のデータを変更する。
                VERSIONS.sync(work)
                run('git', '-C', str(work), 'add', '--', *PATHS)
                if not run('git', '-C', str(work), 'diff', '--cached', '--name-only').strip():
                    continue
                run('git', '-C', str(work), '-c', 'core.hooksPath=/dev/null',
                    '-c', 'user.name=github-actions[bot]',
                    '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com',
                    'commit', '-m', 'chore(postgresql): sync images and vendored PGO chart')
                # 通常 push により、同時に変更された PR の上書きを拒否する。
                run('git', '-C', str(work), 'push', 'origin', f'HEAD:refs/heads/{head["ref"]}')
                print(f'PostgreSQL の関連ファイルを同期: PR #{pr["number"]}')
            finally:
                run('git', 'worktree', 'remove', '--force', str(work), cwd=ROOT)


if __name__ == '__main__':
    main()
