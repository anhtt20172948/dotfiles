#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
# Colour sources and upstream assets. These exceptions are data, not active UI config.
prefixes = (
    '.config/kitty/kitty-themes/',  # Vendored alternative terminal palettes.
    '.config/yazi/flavors/',  # Upstream packages retained by package.toml; theme.toml uses ANSI.
    'docs/', 'tests/',  # Documentation, assertions and third-party fixtures.
)
files = {
    '.config/kitty/current-theme.conf',  # The terminal fallback palette.
    '.config/kitty/dank-theme.conf',  # Optional DMS-generated terminal palette.
    '.config/kitty/colors-matugen.conf',  # Alternate generated terminal palette.
    '.config/kitty/colors-wallust.conf',  # Alternate generated terminal palette.
    '.config/kitty/custom-tabs-colors.conf',  # Kitty tab palette.
    '.config/claude-mods/crew-watch/tests/theme.test.ts',  # Named-palette regression assertions.
    '.config/claude-mods/crew-watch/hooks/theme.ts',  # Explicitly selectable named palettes.
    '.config/claude-mods/pixel-pet/hooks/lib/sprite.ts',  # Sprite artwork pixels, not UI theme colours.
}
pattern = re.compile(r'(?<![\w#])#(?:[a-fA-F0-9]{6}|[a-fA-F0-9]{3})(?![\w])')
violations = []
for name in subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0'):
    path = root / name
    if not name or name.startswith(prefixes) or name in files or path.name in ('README.md', 'lazy-lock.json', 'package-lock.json', 'bun.lock'):
        # README prose and generated dependency locks are not active colour config.
        continue
    if path.is_symlink() or not path.is_file():
        continue
    try:
        content = path.read_text()
    except UnicodeDecodeError:
        continue
    for number, line in enumerate(content.splitlines(), 1):
        if pattern.search(line):
            violations.append(f'{name}:{number}: {line.strip()}')
if violations:
    sys.exit('Hex colours belong in kitty palettes (or a documented asset exception):\n' + '\n'.join(violations))
print('palette consistency: OK')
PY
