#!/usr/bin/env bash
set -euo pipefail
f() {
	local x=$1
	if [[ -n "$x" ]]; then echo "$x"; fi
}
f hello
