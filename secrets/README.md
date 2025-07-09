# Secret Management

このディレクトリは、Sealed Secretsを使用したSecret管理を行います。

## Sealed Secretsとは

Sealed Secretsは、KubernetesのSecretを暗号化してGitリポジトリで安全に管理できる仕組みです。

## セットアップ

### 1. Sealed Secrets Controllerの導入

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml
```

### 2. kubeseal CLIのインストール

```bash
# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/kubeseal-0.18.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.18.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## 使用方法

### 1. Secret作成

```bash
# 通常のSecretを作成（ファイルには保存しない）
kubectl create secret generic slack-secret \
  --from-literal=token=your-slack-token \
  --dry-run=client -o yaml > /tmp/slack-secret.yaml
```

### 2. Sealed Secretに変換

```bash
# Sealed Secretに変換
kubeseal -f /tmp/slack-secret.yaml -w secrets/sealed-secrets/slack-sealed.yaml

# 元のSecretファイルを削除
rm /tmp/slack-secret.yaml
```

### 3. 適用

```bash
kubectl apply -f secrets/sealed-secrets/slack-sealed.yaml
```

## ディレクトリ構造

```
secrets/
├── README.md                    # このファイル
├── sealed-secrets/              # 暗号化されたSecret
│   ├── slack-sealed.yaml
│   ├── harbor-sealed.yaml
│   └── github-runner-sealed.yaml
├── examples/                    # 使用例
│   └── create-secrets.sh
└── kustomization.yaml          # すべてのSealed Secretsをまとめて適用
```

## 注意事項

- **絶対に平文のSecretをリポジトリにコミットしないでください**
- Sealed Secretsは特定のクラスターの公開鍵で暗号化されるため、他のクラスターでは使用できません
- Sealed Secrets Controllerの秘密鍵をバックアップしてください

## バックアップ

Sealed Secrets Controllerの秘密鍵をバックアップ：

```bash
kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
```

## 復元

新しいクラスターでの秘密鍵復元：

```bash
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```