#!/bin/sh
# 空の DB や復元途中の DB で Harbor が初期化を始めることを防ぐ。
set -eu
until [ "$(psql -XAt -v ON_ERROR_STOP=1 -c "SELECT generation FROM platform_bootstrap.migration WHERE application = 'harbor'" 2>/dev/null)" = "$MIGRATION_GENERATION" ]; do
  echo 'Waiting for PostgreSQL credentials, TLS, and verified Harbor restore'
  sleep 5
done
echo 'PostgreSQL restore gate verified'
