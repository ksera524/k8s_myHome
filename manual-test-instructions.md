# Pulumi ESC 手動テスト手順

現在、harborとharbor_ciキーが取得できるかテストします。

## 1. 環境変数設定とテスト実行

```bash
# PATH更新
export PATH=$PATH:$HOME/.pulumi/bin

# Pulumi Access Tokenを設定（あなたのトークンに置き換え）
export PULUMI_ACCESS_TOKEN="pul-your-actual-token-here"

# テストスクリプト実行
./test-pulumi-esc-simple.sh
```

## 2. 予想される結果

### ✅ 成功パターン
```
=== Pulumi ESC 接続テスト ===
✓ Pulumi CLI は利用可能です
✓ PULUMI_ACCESS_TOKEN が設定されています
✓ Pulumi ログイン成功
✓ ESC environment が存在します
--- Environment Content ---
values:
  harbor: "MySecurePassword123"
  harbor_ci: "MySecurePassword456"
--- End of Environment ---
✓ harbor キーが存在します
✓ harbor_ci キーが存在します
=== テスト完了 ===
```

### ❌ 失敗パターン（environment不存在）
```
❌ ESC environment 'ksera/k8s/secret' が見つかりません
利用可能な environments:
  ksera/k8s/dev
  ksera/k8s/prod
```

### ❌ 失敗パターン（キー不存在）
```
✓ ESC environment が存在します
--- Environment Content ---
values:
  other_key: "some_value"
--- End of Environment ---
❌ harbor キーが見つかりません
❌ harbor_ci キーが見つかりません
```

## 3. 問題の対処法

### ESC environment が存在しない場合
```bash
# 新しいenvironment作成
pulumi env init ksera/k8s/secret

# 設定
cat > /tmp/esc-config.yaml << 'EOF'
values:
  harbor: "MySecureHarborPassword123"
  harbor_ci: "MySecureHarborCIPassword456"
EOF

pulumi env set ksera/k8s/secret --file /tmp/esc-config.yaml
```

### キーが存在しない場合
```bash
# 既存environmentにキー追加
pulumi env set ksera/k8s/secret harbor "MySecureHarborPassword123"
pulumi env set ksera/k8s/secret harbor_ci "MySecureHarborCIPassword456"
```

## 4. 確認コマンド
```bash
# Environment確認
pulumi env get ksera/k8s/secret --show-secrets

# 利用可能なenvironments確認
pulumi env ls ksera/k8s
```

テスト結果をお知らせください。