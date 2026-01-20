# k8s_myHome ドキュメント

## 📚 ドキュメント一覧

### 🏗️ アーキテクチャ
- [Kubernetesアーキテクチャ](kubernetes-architecture.md) - クラスター構成とネットワーク設計
- [GitOps設計](gitops-design.md) - ArgoCD App-of-Appsパターン実装

### 📖 セットアップガイド
- [クイックスタート](quickstart.md) - 初回セットアップ手順
- [詳細セットアップガイド](setup-guide.md) - ステップバイステップの構築手順

### 🔧 運用ガイド
- [運用ガイド](operations-guide.md) - 日常運用とメンテナンス
- [トラブルシューティング](troubleshooting.md) - 問題解決ガイド

### 🚀 アプリケーション
- [アプリケーション管理](applications.md) - デプロイされているアプリケーション

### 📋 リファレンス
- [Kubernetesアップグレード](kubernetes-upgrade-guide.md) - バージョン更新手順

## 🎯 プロジェクト概要

**k8s_myHome**は、本格的なホームKubernetesインフラストラクチャプロジェクトです。k3sから仮想化インフラストラクチャ上の完全な3ノードクラスターへの移行を実現し、GitOpsベースの完全自動化されたデプロイメントを提供します。

### 主な特徴

- ✅ **フェーズ実行**: `make all`でPhase 1〜5を順番に実行
- ✅ **GitOps駆動**: ArgoCD App-of-Appsパターン
- ✅ **プライベートレジストリ**: Harbor統合
- ✅ **CI/CD統合**: GitHub Actions Runner Controller
- ✅ **Secret管理**: External Secrets Operator + Pulumi ESC
- ✅ **ロードバランサー**: MetalLB
- ✅ **Ingress/TLS**: NGINX + cert-manager

### アーキテクチャ概要

```
┌─────────────────────────────────────────────────┐
│                  ホストマシン                     │
│             Ubuntu 24.04 LTS                    │
├─────────────────────────────────────────────────┤
│              QEMU/KVM + libvirt                 │
├─────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │Control   │  │ Worker1  │  │ Worker2  │    │
│  │Plane     │  │          │  │          │    │
│  │.122.10   │  │ .122.11  │  │ .122.12  │    │
│  └──────────┘  └──────────┘  └──────────┘    │
├─────────────────────────────────────────────────┤
│           Kubernetes v1.29.0 + Flannel          │
├─────────────────────────────────────────────────┤
│  MetalLB | NGINX | cert-manager | ArgoCD       │
│  Harbor | External Secrets | GitHub Actions     │
└─────────────────────────────────────────────────┘
```

### クイックスタート

```bash
# 1. リポジトリクローン
git clone https://github.com/ksera524/k8s_myHome.git
cd k8s_myHome

# 2. 設定ファイル準備
cp automation/settings.toml.example automation/settings.toml
# settings.tomlを編集して必要な値を設定

# 3. 完全自動デプロイ
make all

# 4. 状態確認
make phase5
```

詳細は[クイックスタートガイド](quickstart.md)を参照してください。

## 📞 サポート

- **Issues**: [GitHub Issues](https://github.com/ksera524/k8s_myHome/issues)
- **Documentation**: このディレクトリ内のドキュメント

## 📝 ライセンス

このプロジェクトはMITライセンスの下で公開されています。
