#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
python3 "$ROOT/tests/ai_acct_quota.py"
