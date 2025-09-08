# 統一ログ機能ガイド

## 📋 概要

すべてのスクリプトで共通のログ出力形式を提供する統一ログ機能を実装しました。

## 🎯 特徴

- **統一されたログ形式**: すべてのスクリプトで一貫したログ出力
- **ログレベル制御**: DEBUG, INFO, WARNING, ERROR, CRITICAL
- **複数の出力先**: コンソール、ファイル、JSON形式
- **後方互換性**: 既存の `print_*` 関数をサポート
- **settings.toml 統合**: ログ設定を自動読み込み

## 📁 ファイル構成

```
automation/scripts/
├── common-logging.sh    # 統一ログ機能（メイン）
├── common-colors.sh      # 後方互換性ラッパー
├── settings-loader.sh    # settings.toml統合
└── test-logging.sh       # テストスクリプト
```

## 🔧 使用方法

### 基本的な使用

```bash
#!/bin/bash
# ログ機能を読み込み
source "$(dirname "$0")/common-logging.sh"

# ログ出力
log_info "処理を開始します"
log_success "処理が完了しました"
log_warning "注意が必要です"
log_error "エラーが発生しました"
```

### ログレベル

| レベル | 値 | 関数 | 絵文字 | 用途 |
|-------|---|------|--------|------|
| DEBUG | 0 | `log_debug()` | 🔍 | デバッグ情報 |
| INFO | 1 | `log_info()` | ℹ️ | 一般情報 |
| STATUS | 1 | `log_status()` | 📋 | ステータス更新 |
| SUCCESS | 1 | `log_success()` | ✅ | 成功メッセージ |
| WARNING | 2 | `log_warning()` | ⚠️ | 警告 |
| ERROR | 3 | `log_error()` | ❌ | エラー |
| CRITICAL | 4 | `log_critical()` | 🚨 | 致命的エラー |

### ログレベル設定

```bash
# デフォルトはINFO（1）
set_log_level debug    # すべてのメッセージを表示
set_log_level warning  # WARNING以上のみ表示
set_log_level error    # ERROR以上のみ表示

# 環境変数でも設定可能
export LOG_LEVEL=debug
```

### ファイル出力

```bash
# ログファイルを設定
set_log_file "/var/log/k8s-myhome.log"

# 以降のログはファイルとコンソールの両方に出力
log_info "これはファイルにも記録されます"
```

### JSON形式出力

```bash
# JSON形式に切り替え
set_log_format json
log_info "構造化ログ"
# 出力: {"timestamp":"2025-01-27 10:00:00","level":"INFO","message":"構造化ログ","file":"script.sh","line":10}

# テキスト形式に戻す
set_log_format text
```

## 🔄 後方互換性

既存のスクリプトは変更不要です：

```bash
# 従来の関数も使用可能
print_status "ステータス"
print_success "成功"
print_warning "警告"
print_error "エラー"
print_debug "デバッグ"
```

## ⚙️ settings.toml 統合

`settings.toml` でログ設定を定義：

```toml
[logging]
log_dir = "/var/log/k8s-myhome"
log_level = "INFO"
debug = false
verbose = false
```

自動的に読み込まれて適用されます。

## 🧪 テスト

テストスクリプトで動作確認：

```bash
./scripts/test-logging.sh
```

## 📝 移行ガイド

### 新規スクリプト

```bash
#!/bin/bash
source "$(dirname "$0")/common-logging.sh"

log_info "新しいログ機能を使用"
```

### 既存スクリプト

1. **方法1**: そのまま使用（後方互換）
   ```bash
   source common-colors.sh  # 自動的にcommon-logging.shを読み込み
   print_status "既存の関数を使用"
   ```

2. **方法2**: 新機能に移行
   ```bash
   source common-logging.sh
   log_status "新しい関数を使用"
   ```

## 🎨 カスタマイズ

### カスタムプレフィックス

```bash
# プロジェクト固有のプレフィックスを追加
my_log() {
    log_info "[MyProject] $1"
}
```

### 条件付きログ

```bash
# verboseモードの実装
[[ "$VERBOSE" == "true" ]] && log_debug "詳細情報"
```

## 📊 ログ分析

ログファイルの分析例：

```bash
# エラーのみ抽出
grep "\[ERROR\]" /var/log/k8s-myhome.log

# JSON形式のログをjqで処理
cat logs.json | jq 'select(.level == "ERROR")'

# タイムスタンプでソート
sort -t'[' -k2 /var/log/k8s-myhome.log
```

## ✅ 利点

1. **一貫性**: すべてのスクリプトで同じログ形式
2. **可読性**: 絵文字による視覚的な区別
3. **柔軟性**: レベル制御、複数の出力形式
4. **保守性**: 中央集約型のログ機能管理
5. **互換性**: 既存コードの変更不要

---

作成日: 2025-01-27
バージョン: 1.0.0