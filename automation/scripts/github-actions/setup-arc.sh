#!/bin/bash

# GitHub Actions Runner Controller (ARC) セットアップスクリプト
# 注意: 現在ARCはGitOps経由で管理されています (manifests/platform/github-actions)
# このスクリプトは互換性のため保持されていますが、実際のデプロイはマニフェスト形式で行われます

set -euo pipefail

echo "==============================================="
echo "⚠️  GitHub Actions Runner Controller (ARC) 移行のお知らせ"
echo "==============================================="
echo ""
echo "🎯 ARC は GitOps 形式に移行されました:"
echo "   📁 manifests/platform/github-actions/"
echo "   ├── arc-controller.yaml           # 公式ARC Controller"
echo "   ├── multi-repo-runner-scalesets.yaml  # 複数リポジトリ対応RunnerScaleSet群"
echo "   ├── external-secrets.yaml        # ESO統合認証情報"
echo "   └── github-actions-rbac.yaml     # RBAC設定"
echo ""
echo "🚀 特徴:"
echo "   • 公式GitHub ARC (v0.12.1) 使用"
echo "   • 複数リポジトリ対応 (k8s_myHome, slack.rs, shared)"
echo "   • Individual PAT による認証"
echo "   • ESO統合による安全な認証情報管理"
echo "   • ArgoCD App-of-Apps 自動デプロイ"
echo ""
echo "📋 利用可能なRunnerScaleSet:"
echo "   • k8s-myhome-runners  (k8s_myHome リポジトリ専用)"
echo "   • slack-rs-runners    (slack.rs リポジトリ専用)"  
echo "   • shared-runners      (汎用・新規リポジトリ対応)"
echo ""
echo "⭐ Workflow内での使用方法:"
echo "   runs-on: k8s-myhome-runners  # リポジトリ専用"
echo "   runs-on: slack-rs-runners    # slack.rs専用"
echo "   runs-on: shared-runners      # 汎用"
echo ""
echo "✅ 設定は完了しています。新しい形式をお楽しみください！"
echo "==============================================="

# GitOps管理への移行を通知して終了
exit 0