"""既存の状態メトリクスを集計し、週次レポートを Slack へ送る。"""
import argparse
import datetime as dt
import html
import json
import math
import os
from pathlib import Path
import sys
import urllib.parse
import urllib.request

# bool 比較で正常値も残し、0 件とデータ欠損を区別する。
CHECKS = [
    ('Node Ready 異常', 'node', 'kube_node_status_condition{condition="Ready",status="true"} == bool 0'),
    ('Pod Ready 異常', 'namespace,pod', '(kube_pod_status_ready{condition="true"} == bool 0) and on(namespace,pod,uid) (kube_pod_status_phase{phase=~"Pending|Running|Unknown"} == 1)'),
    ('Deployment replica 不足', 'namespace,deployment', 'kube_deployment_spec_replicas > bool kube_deployment_status_replicas_available'),
    ('PVC Pending / Lost', 'namespace,persistentvolumeclaim', 'kube_persistentvolumeclaim_status_phase{phase=~"Pending|Lost"} == bool 1'),
    ('ArgoCD 同期異常', 'namespace,application', 'kube_argocd_application_sync_status{status=~"OutOfSync|Unknown"} == bool 1'),
    ('ArgoCD health 異常', 'namespace,application', 'kube_argocd_application_health_status{status=~"Degraded|Missing|Unknown"} == bool 1'),
    ('ExternalSecret Ready 異常', 'namespace,externalsecret', 'kube_externalsecret_status_condition{type="Ready"} == bool 0'),
    ('Gateway Programmed 異常', 'namespace,gateway', 'kube_gateway_status_condition{type="Programmed"} == bool 0'),
    ('Certificate Ready 異常', 'namespace,certificate', 'kube_certificate_status_condition{type="Ready"} == bool 0'),
]
RESTARTS = 'topk(5, sum by(namespace,pod,container) (increase(kube_pod_container_status_restarts_total[7d])))'


def query(base, expression, end):
    params = urllib.parse.urlencode({'query': expression, 'time': end.timestamp()})
    with urllib.request.urlopen(base.rstrip('/') + '/api/v1/query?' + params, timeout=20) as response:
        data = json.load(response)
    if data.get('status') != 'success' or data.get('data', {}).get('resultType') != 'vector':
        raise ValueError('metrics API の応答が不正')
    rows = data['data']['result']
    if any(not math.isfinite(float(r['value'][1])) for r in rows):
        raise ValueError('有限値でないメトリクス')
    return rows


def summarize(rows):
    if not rows:
        return 'データなし'
    return f'{sum(float(r["value"][1]) > 0 for r in rows)} / {len(rows)} 対象'


def report(fetch, end):
    jst = dt.timezone(dt.timedelta(hours=9))
    start = end - dt.timedelta(days=7)
    lines = ['*Kubernetes 週次レポート / home-lab*',
             f'{start.astimezone(jst):%Y-%m-%d %H:%M} ～ {end.astimezone(jst):%Y-%m-%d %H:%M} JST',
             '*過去 7 日に異常を観測した対象数 / 観測対象数*']
    errors = []
    for title, labels, expr in CHECKS:
        try:
            rows = fetch(f'max by ({labels}) (max_over_time(({expr})[7d:5m]))')
            lines.append(f'• {title}: {summarize(rows)}')
        except Exception:
            # URL や認証情報を含み得る例外本文はログ・Slack に出さない。
            errors.append(title)
            lines.append(f'• {title}: 取得失敗')
    lines.append('*コンテナ再起動ランキング（上位 5 件・推定回数）*')
    try:
        rows = fetch(RESTARTS)
        positive = sorted((r for r in rows if float(r['value'][1]) > 0),
                          key=lambda r: float(r['value'][1]), reverse=True)
        for row in positive:
            labels = row['metric']
            name = '/'.join(labels.get(k, '?') for k in ('namespace', 'pod', 'container'))
            lines.append(f'• {html.escape(name)}: 約 {float(row["value"][1]):.1f} 回')
        if not positive:
            lines.append('• 再起動なし' if rows else '• データなし')
    except Exception:
        errors.append('再起動ランキング')
        lines.append('• 取得失敗')
    lines.append('状態は 5 分間隔の観測です。短い異常・収集停止中の異常・欠損 condition は検出できません。'
                 '対象数は期間中に観測できたリソース数で、同名 Pod の再作成はまとめます。')
    if errors:
        lines.append('⚠ 一部の取得に失敗したため、不完全なレポートです。')
    return '\n'.join(lines), errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    end = dt.datetime.now(dt.timezone.utc)
    base = os.environ.get('VICTORIA_METRICS_URL', 'http://victoria-metrics:8428')
    text, errors = report(lambda expr: query(base, expr, end), end)
    if args.dry_run:
        print(text)
    else:
        try:
            url = Path('/etc/slack/webhook-url').read_text().strip()
            if not url.startswith('https://hooks.slack.com/services/'):
                raise ValueError('invalid webhook')
            request = urllib.request.Request(url, data=json.dumps({'text': text}).encode(),
                                             headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(request, timeout=20) as response:
                if response.read().strip() != b'ok':
                    raise ValueError('Slack rejected message')
        except Exception:
            print('週次レポートの Slack 送信に失敗しました。', file=sys.stderr)
            return 1
        print('週次レポートを Slack に送信しました。')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
