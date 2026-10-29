#!/usr/bin/env bash
set -euo pipefail

# ツール設定はイメージ内の固定パスから解決し、検証対象はマウント先で実行する。
cd /opt/toolchain
exec mise exec -- bash -c 'cd /work; exec "$@"' -- "$@"
