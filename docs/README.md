# k8s_myHome プロジェクト

[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.29.0-blue)](https://kubernetes.io/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-orange)](https://github.com/features/actions)
[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-brightgreen)](https://argoproj.github.io/cd/)

## 🎯 プロジェクト概要

**k8s_myHome**は、ホームラボ環境向けのプロダクショングレードKubernetesインフラストラクチャプロジェクトです。k3sから本格的な3ノードクラスターへの移行を実現し、完全自動化されたデプロイメントと運用を提供します。

### 主な特徴

- 🚀 **完全自動化デプロイメント**: `make all`だけで全環境構築
- 🔄 **GitOpsベース**: ArgoCDによる宣言的なアプリケーション管理
- 🏗️ **フェーズベース構築**: 段階的な環境構築で確実性を向上
- 🛡️ **プロダクショングレード**: 本番環境レベルの可用性と信頼性
- 📦 **プライベートレジストリ**: Harbor統合による安全なコンテナ管理
- 🤖 **CI/CD統合**: GitHub Actions + セルフホステッドランナー

## 🏗️ アーキテクチャ

### インフラストラクチャ構成
```
┌─────────────────────────────────────────────────┐
│                 Host (Ubuntu 24.04)              │
├─────────────────────────────────────────────────┤
│                  QEMU/KVM + libvirt              │
├─────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │ Control  │  │  Worker  │  │  Worker  │     │
│  │  Plane   │  │    1     │  │    2     │     │
│  │  .10     │  │   .11    │  │   .12    │     │
│  └──────────┘  └──────────┘  └──────────┘     │
└─────────────────────────────────────────────────┘
```

### 主要コンポーネント

| コンポーネント | 説明 | バージョン |
|------------|------|----------|
| **Kubernetes** | コンテナオーケストレーション | v1.29.0 |
| **MetalLB** | LoadBalancerサービス | v0.13.12 |
| **NGINX Ingress** | L7ロードバランサー | v1.9.4 |
| **ArgoCD** | GitOpsエンジン | v2.9.3 |
| **Harbor** | コンテナレジストリ | v2.9.1 |
| **cert-manager** | 証明書管理 | v1.13.3 |
| **External Secrets** | シークレット管理 | v0.9.11 |

## 🚀 クイックスタート

### 前提条件

- Ubuntu 24.04 LTS（ホストOS）
- 最小リソース要件:
  - CPU: 8コア以上
  - メモリ: 24GB以上
  - ストレージ: 200GB以上
- インターネット接続

### ワンステップデプロイ

```bash
# リポジトリクローン
git clone https://github.com/ksera524/k8s_myHome.git
cd k8s_myHome

# 設定ファイル準備
cp automation/settings.toml.example automation/settings.toml
# settings.tomlを編集（GitHub PAT、Pulumi Access Token等）

# 完全自動デプロイ
make all
```

詳細は[QUICKSTART.md](QUICKSTART.md)を参照してください。

## 📁 プロジェクト構造

```
k8s_myHome/
├── automation/           # 自動化スクリプト
│   ├── host-setup/      # ホスト準備
│   ├── infrastructure/  # VM + Kubernetes
│   └── platform/        # プラットフォームサービス
├── manifests/           # Kubernetesマニフェスト
│   ├── 00-bootstrap/    # ArgoCD App-of-Apps
│   ├── resources/       # リソース定義
│   └── apps/           # アプリケーション
├── docs/               # ドキュメント
│   ├── architecture/   # アーキテクチャ
│   ├── operations/     # 運用
│   └── development/    # 開発
└── diagrams/           # 構成図（SVG）
```

## 🔧 主要コマンド

### 環境管理
```bash
make all                  # 完全デプロイ
make add-runner REPO=xxx # GitHub Actionsランナー追加
```

### アクセス情報
- **ArgoCD**: https://argocd.qroksera.com
- **Harbor**: http://192.168.122.100
- **LoadBalancer IP範囲**: 192.168.122.100-150

### トラブルシューティング
```bash
# クラスターアクセス
ssh k8suser@192.168.122.10
kubectl get nodes

# ログ確認
kubectl logs -n argocd deployment/argocd-server
kubectl get events --all-namespaces

# VM管理
sudo virsh list --all
sudo virsh console k8s-control-plane-1
```

## 📚 ドキュメント

- [アーキテクチャ](architecture/README.md) - システム設計と構成
- [運用ガイド](operations/deployment-guide.md) - デプロイと運用手順
- [開発ガイド](development/setup.md) - 開発環境構築
- [トラブルシューティング](operations/troubleshooting.md) - 問題解決

## 🤝 コントリビューション

プルリクエストは歓迎します！詳細は[CONTRIBUTING.md](development/contributing.md)を参照してください。

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。詳細は[LICENSE](LICENSE)を参照してください。

## 🔗 関連リンク

- [プロジェクトリポジトリ](https://github.com/ksera524/k8s_myHome)
- [イシュートラッカー](https://github.com/ksera524/k8s_myHome/issues)
- [ディスカッション](https://github.com/ksera524/k8s_myHome/discussions)

## 📝 注意事項

- このプロジェクトは日本語を優先言語としています
- 本番環境での使用前に十分なテストを実施してください
- セキュリティ設定は環境に応じて適切に調整してください

---
*Last updated: 2025-01-09*