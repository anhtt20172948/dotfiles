#!/usr/bin/env bash
# Use the installed scripts' /bin/bash, including stock Bash 3.2 on macOS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 "$ROOT/tests/remote_helpers.py"
