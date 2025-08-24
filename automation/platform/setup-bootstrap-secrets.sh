#!/bin/bash
# Bootstrap Secrets設定をplatform-deployから呼び出すスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bootstrap Secretsの設定を実行
"$SCRIPT_DIR/../scripts/setup-bootstrap-secrets.sh"