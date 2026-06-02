#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found" >&2
  exit 1
fi

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "python3 PyYAML not found" >&2
  exit 1
fi

"$ROOT_DIR/automation/scripts/ci/policy-check.py"
