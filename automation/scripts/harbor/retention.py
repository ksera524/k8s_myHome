#!/usr/bin/env python3
"""稼働中・直前正常版・候補の最大3 digestを、Harbor標準保持処理で残す。"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

DIGEST = re.compile(r"sha256:[0-9a-f]{64}")


def kubectl(*args):
    return json.loads(subprocess.check_output(
        ['kubectl', '--request-timeout=20s', *args, '-o', 'json'], text=True, timeout=30))


def digest(value):
    if not DIGEST.fullmatch(value):
        raise ValueError(f'不正なdigest: {value}')
    return value


def image_digest(image, repository):
    # 旧hostnameと内部hostnameは同一Harborの別名。
    name = image.split('/', 1)[-1]
    if not (name.startswith(repository + ':') or name.startswith(repository + '@')):
        return None
    if '@' not in name:
        raise ValueError(f'digest固定でない参照があります: {image}')
    return digest(name.rsplit('@', 1)[1])


def observed_current(app, workloads, repository):
    status = app.get('status', {})
    if status.get('health', {}).get('status') != 'Healthy' or status.get('sync', {}).get('status') != 'Synced':
        raise ValueError('ApplicationがSynced/Healthyではありません。保持処理を停止します')
    if app.get('operation') or status.get('operationState', {}).get('phase') in ('Running', 'Terminating'):
        raise ValueError('ArgoCDの同期処理中です')
    images = status.get('summary', {}).get('images', [])
    current = {d for image in images if (d := image_digest(image, repository))}
    if len(current) != 1:
        raise ValueError('稼働版を一意に特定できません')
    references = set()
    matched = 0
    ready_pods = 0
    for item in workloads['items']:
        kind = item['kind']
        if kind == 'Pod':
            if item.get('status', {}).get('phase') in ('Succeeded', 'Failed'):
                continue
            spec = item['spec']
        elif kind == 'CronJob':
            spec = item['spec']['jobTemplate']['spec']['template']['spec']
        else:
            if kind == 'Job' and any(c.get('type') in ('Complete', 'Failed') and c.get('status') == 'True'
                                     for c in item.get('status', {}).get('conditions', [])):
                continue
            spec = item['spec']['template']['spec']
        for container in spec.get('containers', []) + spec.get('initContainers', []):
            d = image_digest(container['image'], repository)
            if d:
                references.add(d)
                matched += 1
                if kind == 'Pod' and any(c.get('type') == 'Ready' and c.get('status') == 'True'
                                         for c in item.get('status', {}).get('conditions', [])):
                    ready_pods += 1
        # 実際に実行されたイメージがPod specと食い違う場合も削除を止める。
        if kind == 'Pod':
            for container in item.get('status', {}).get('containerStatuses', []) + item.get('status', {}).get('initContainerStatuses', []):
                if image_digest(container.get('image', ''), repository):
                    image_id = container.get('imageID', '')
                    if '@' in image_id:
                        references.add(digest(image_id.rsplit('@', 1)[1]))
    if not matched or not ready_pods or references != current:
        raise ValueError('workload/実行中Podのdigestが稼働版と一致しません。切替完了後に再実行してください')
    return current.pop()


def plan(artifacts, current, previous):
    by_digest = {digest(a['digest']): a for a in artifacts}
    latest = [a['digest'] for a in artifacts if any(t['name'] == 'latest' for t in a.get('tags') or [])]
    if len(latest) != 1:
        raise ValueError('latestを一意に特定できません')
    roles = {'current': digest(current), 'candidate': latest[0]}
    if previous:
        roles['previous'] = digest(previous)
    keep = set(roles.values())
    if not keep <= by_digest.keys():
        raise ValueError('保護対象のartifactがHarborにありません')
    # OCI indexの子manifestを独立した世代と誤認しない。初期対象はdocker saveの単一platform。
    if any(a.get('references') or a.get('type') != 'IMAGE' for a in artifacts):
        raise ValueError('index/非IMAGE artifactを検出しました。この保守コマンドの対象外です')
    return {
        'roles': roles,
        'keep': sorted(keep),
        'delete': sorted(by_digest.keys() - keep),
        'logical_bytes_before': sum(a.get('size', 0) for a in artifacts),
        'logical_bytes_keep': sum(by_digest[d].get('size', 0) for d in keep),
    }


def policy(project_id, repository, keep):
    # digestごとに固定タグを作り、標準のalwaysルールでそのartifactを保護する。
    # project全体で1 policyのため、pilot以外には別の「全保持」ルールを付ける。
    def rule(selector, pattern):
        return {'priority': 0, 'disabled': False, 'action': 'retain', 'template': 'always',
                'params': {},
                'tag_selectors': [{'kind': 'doublestar', 'decoration': 'matches',
                                   'pattern': pattern, 'extras': json.dumps({'untagged': selector == 'repoExcludes'})}],
                'scope_selectors': {'repository': [{'kind': 'doublestar',
                                                   'decoration': selector, 'pattern': repository}]}}
    tags = ['retain-' + d[7:] for d in keep]
    pattern = tags[0] if len(tags) == 1 else '{' + ','.join(tags) + '}'
    return {'algorithm': 'or', 'scope': {'level': 'project', 'ref': project_id},
            # Harborの更新APIは非定期実行を空kindで表す（Manualは更新時に拒否される）。
            'trigger': {'kind': ''},
            'rules': [rule('repoMatches', pattern),
                      rule('repoExcludes', '**')]}


class Harbor:
    def __init__(self, url, username, password):
        self.url = url.rstrip('/') + '/api/v2.0'
        self.auth = 'Basic ' + base64.b64encode(f'{username}:{password}'.encode()).decode()

    def request(self, method, path, payload=None):
        req = urllib.request.Request(self.url + path, method=method,
                                     data=json.dumps(payload).encode() if payload is not None else None,
                                     headers={'Authorization': self.auth, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as exc:
            # レスポンス本文には資格情報等が含まれる可能性があるため表示しない。
            raise RuntimeError(f'Harbor {method} {path}: HTTP {exc.code}') from None

    def pages(self, path):
        result = []
        page = 1
        while True:
            chunk = self.request('GET', f'{path}{"&" if "?" in path else "?"}page={page}&page_size=100')
            result.extend(chunk)
            if len(chunk) < 100:
                return result
            page += 1


def snapshot(args, client):
    app = kubectl('-n', 'argocd', 'get', 'application', args.application)
    workloads = kubectl('-n', app['spec']['destination']['namespace'], 'get',
                        'deployments,statefulsets,daemonsets,cronjobs,jobs,pods')
    current = observed_current(app, workloads, f'{args.project}/{args.repository}')
    artifacts = client.pages(f'/projects/{args.project}/repositories/{args.repository}/artifacts?with_tag=true')
    result = plan(artifacts, current, args.previous)
    return result


def quota_limit(quota, proposed):
    used = quota['used']['storage']
    if proposed <= used:
        raise ValueError('容量上限が現在の使用量以下です')
    existing = quota['hard'].get('storage', -1)
    return min(existing, proposed) if existing > 0 else proposed


def canonical(value):
    # Harborが採番するidを除いて、レビューしたpolicyと現在値を比較する。
    if isinstance(value, dict):
        return {k: ({'kind': ''} if k == 'trigger' and v.get('kind', '') in ('', 'Manual') else canonical(v))
                for k, v in value.items()
                if k != 'id' and not (k == 'priority' and v == 0)
                and not (k == 'disabled' and v is False)
                and not (k == 'params' and v == {})}
    if isinstance(value, list):
        return [canonical(v) for v in value]
    return value


def wait_execution(client, policy_id, before, dry_run):
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        executions = client.pages(f'/retentions/{policy_id}/executions')
        new = [e for e in executions if e['id'] not in before and e['dry_run'] == dry_run]
        if len(new) > 1:
            raise RuntimeError('並行した保持処理を検出しました。Harborで実行履歴を確認してください')
        if new:
            execution = new[0]
            if execution['status'] == 'Success':
                print(json.dumps({'execution': execution['id'], 'dry_run': dry_run, 'status': 'Success'}))
                return execution['id']
            if execution['status'] not in ('Pending', 'Running'):
                raise RuntimeError(f'保持処理が正常終了しませんでした: {execution["status"]}')
        time.sleep(2)
    raise RuntimeError('保持処理の完了待ちがタイムアウトしました。公開停止を維持しHarborで確認してください')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='https://harbor.internal.qroksera.com')
    parser.add_argument('--project', default='sandbox', choices=['sandbox'])
    parser.add_argument('--repository', default='api-hub', choices=['api-hub'])
    parser.add_argument('--application', default='api-hub', choices=['api-hub'])
    previous = parser.add_mutually_exclusive_group(required=True)
    previous.add_argument('--previous', help='運用記録で正常稼働を確認した直前版のsha256 digest')
    previous.add_argument('--no-previous-known', action='store_true', help='初期移行で直前正常版が不明')
    parser.add_argument('--output', type=Path, required=True, help='レビュー用plan JSONの保存先')
    parser.add_argument('--reviewed-plan', type=Path, help='事前にレビューしたplan JSON。反映には必須')
    parser.add_argument('--quota-bytes', type=int, default=4 * 1024 ** 3, help='sandbox容量上限。既定4 GiB、既存の厳しい上限は維持')
    parser.add_argument('--apply', action='store_true', help='タグ・標準保持設定を反映しdry runを実行')
    parser.add_argument('--maintenance', action='store_true', help='公開・Image Updater・自動同期の停止と実行中処理の完了を確認済み')
    parser.add_argument('--delete', action='store_true', help='成功したdry runの後に標準保持処理で削除する')
    parser.add_argument('--replace-policy', type=Path, help='既存policyのGET結果。現在値と一致した場合だけ置換')
    args = parser.parse_args()
    if args.delete and not args.apply:
        parser.error('--deleteには--applyが必要です')
    if args.apply and not args.reviewed_plan:
        parser.error('反映には--reviewed-planが必要です')
    if args.apply and not args.maintenance:
        parser.error('反映には--maintenanceが必要です。停止手順はdocs/harbor-retention.mdを参照')
    password = Path(os.environ['HARBOR_PASSWORD_FILE']).read_text().rstrip('\n')
    client = Harbor(args.url, os.environ.get('HARBOR_USERNAME', 'admin'), password)
    project = client.request('GET', f'/projects/{args.project}')
    selected = snapshot(args, client)
    desired = policy(project['project_id'], args.repository, selected['keep'])
    quotas = client.pages('/quotas?reference=project&reference_id=' + str(project['project_id']))
    if len(quotas) != 1:
        raise ValueError('project容量情報を一意に取得できません')
    quota = quotas[0]
    limit = quota_limit(quota, args.quota_bytes)
    report = {**selected, 'policy': desired,
              'storage': {'used': quota['used'], 'hard': quota['hard'], 'proposed_storage': limit}}
    if args.apply:
        reviewed = json.loads(args.reviewed_plan.read_text())
        # 使用量は他repoのpushでも変わるため、保持対象・削除対象・policy・設定上限を比較する。
        for key in ('roles', 'keep', 'delete', 'policy'):
            if report[key] != reviewed[key]:
                raise ValueError(f'レビュー後に{key}が変わりました。新しいplanを確認してください')
        if reviewed['storage']['proposed_storage'] != limit:
            raise ValueError('レビュー後に容量上限が変わりました')
    # 上書きで以前のレビュー記録を失わない。新規ファイルを指定する。
    with args.output.open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'policy'}, ensure_ascii=False, indent=2))
    if not args.apply:
        return
    if snapshot(args, client) != selected:
        raise RuntimeError('plan作成中に稼働状態またはartifactが変わりました')
    policy_id = project.get('metadata', {}).get('retention_id')
    if policy_id:
        existing = client.request('GET', f'/retentions/{policy_id}')
        if not args.replace_policy or json.loads(args.replace_policy.read_text()) != existing:
            raise RuntimeError('既存policyがあります。GET結果をレビューして--replace-policyで指定してください')
        if existing.get('trigger', {}).get('kind', '') not in ('', 'Manual'):
            raise RuntimeError('既存の定期保持処理を停止してから再実行してください')
    if policy_id and any(e['status'] in ('Pending', 'Running')
                         for e in client.pages(f'/retentions/{policy_id}/executions')):
        raise RuntimeError('保持処理が実行中です')
    client.request('PUT', f'/quotas/{quota["id"]}', {'hard': {**quota['hard'], 'storage': limit}})
    for d in selected['keep']:
        path = f'/projects/{args.project}/repositories/{args.repository}/artifacts/{d}'
        artifact = client.request('GET', path)
        tag = 'retain-' + d[7:]
        if not any(t['name'] == tag for t in artifact.get('tags') or []):
            client.request('POST', path + '/tags', {'name': tag})
    if policy_id:
        client.request('PUT', f'/retentions/{policy_id}', {**desired, 'id': int(policy_id)})
    else:
        client.request('POST', '/retentions', desired)
        policy_id = client.request('GET', f'/projects/{args.project}')['metadata']['retention_id']
    for dry_run in ([True, False] if args.delete else [True]):
        if snapshot(args, client) != selected:
            raise RuntimeError('状態が変わりました。保持処理を実行しません')
        if canonical(client.request('GET', f'/retentions/{policy_id}')) != canonical(desired):
            raise RuntimeError('標準保持設定が変更されています')
        before = {e['id'] for e in client.pages(f'/retentions/{policy_id}/executions')}
        client.request('POST', f'/retentions/{policy_id}/executions', {'dry_run': dry_run})
        wait_execution(client, policy_id, before, dry_run)
    # GCはprojectを跨ぐため、このコマンドから自動実行しない。
    print('標準保持処理を完了しました。GCはHarborの実行履歴・dry runを確認して実施してください')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, KeyError, subprocess.SubprocessError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
