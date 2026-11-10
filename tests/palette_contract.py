#!/usr/bin/env python3
"""The ANSI slot contract (README "Colour consistency"), checked across configs.

Every tool outside Neovim follows the terminal palette by naming ANSI slots, so
the slot a config names decides whether its text is readable. DMS's dank16
palette makes two slots unusable as text, whatever the wallpaper:

  * ANSI 5 (magenta) is a dark container tone, about 1.5-2.5:1 on the background;
  * ANSI 8 (bright black) is a surface tone, about 1.8-2:1;
  * ANSI 0 (black) equals the background, so it is no selection surface.

The checks, over every tracked file outside the documented exceptions:

  1. no truecolor or 256-colour escapes (38;2 / 48;2 / 38;5 / 48;5), no rgb()
     literals outside the Hyprland baselines, no tmux colourN;
  2. no text in ANSI 0, 5 or 8 in tmux styles, fzf specs, shell SGR escapes,
     yazi, lazygit/lazydocker, duckdb and Starship (black on its own coloured
     background, a pill, is fine); no ANSI 0 selection surface; the fzf spec
     in fzf-colors.sh and fzfrc identical;
  3. every text slot those configs use reaches 4.5:1 against the background of
     the fixture palettes: Catppuccin Mocha (kitty's fallback) and a recorded
     DMS dark palette for every slot, and a DMS light palette for the base
     slots 1-7. dank16's light bright slots are lighter by construction, so on
     a light background they are low-contrast whatever a config names.

Usage: palette_contract.py <repo root>
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(sys.argv[1])
FAILURES = []

# Same exceptions as the hex check in palette_consistency_test.sh: colour
# sources, upstream assets and test data, not active UI config.
SKIP_PREFIXES = (
    "docs/",
    "tests/",
)
SKIP_FILES = {
    ".config/kitty/current-theme.conf",
    ".config/kitty/dank-theme.conf",
    ".config/kitty/custom-tabs-colors.conf",
    ".config/claude-mods/crew-watch/tests/theme.test.ts",
    ".config/claude-mods/crew-watch/hooks/theme.ts",
    ".config/claude-mods/pixel-pet/hooks/lib/sprite.ts",
}
SKIP_NAMES = ("README.md", "lazy-lock.json", "package-lock.json", "bun.lock")

TEXT_FORBIDDEN = {5: "magenta (ANSI 5)", 8: "bright black (ANSI 8)"}
TEXT_SLOTS = set()  # (slot, where) for the contrast check


def fail(where, message):
    FAILURES.append("{}: {}".format(where, message))


def tracked_files():
    names = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-z"]).decode().split("\0")
    for name in names:
        path = ROOT / name
        if not name or name.startswith(SKIP_PREFIXES) or name in SKIP_FILES or path.name in SKIP_NAMES:
            continue
        if path.is_symlink() or not path.is_file():
            continue
        try:
            yield name, path.read_text()
        except UnicodeDecodeError:
            continue


def use_text(slot, where):
    if slot == 0:
        fail(where, "text in black (ANSI 0), which is the background in DMS's palette")
    elif slot in TEXT_FORBIDDEN:
        fail(where, "text in {}".format(TEXT_FORBIDDEN[slot]))
    elif 0 <= slot <= 15:
        TEXT_SLOTS.add((slot, where))


# --- 1. fixed colours ---------------------------------------------------------
ESCAPE = re.compile(r"(?:\\033|\\e|\\x1b|\\u001b|\x1b)\[([0-9;]*)m")
RGB_LITERAL = re.compile(r"rgba?\(\s*(?:[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\s*\)|\d{1,3}\s*,)")
TMUX_INDEX = re.compile(r"\b[fb]g=colou?r\d+")


def sgr_params(params):
    """Yield (kind, value) for one SGR parameter list: ('fg'|'bg', slot) or
    ('fixed', text) for 256-colour and truecolor forms."""
    parts = [p for p in params.split(";")]
    i = 0
    while i < len(parts):
        p = parts[i]
        if p in ("38", "48") and i + 1 < len(parts) and parts[i + 1] in ("2", "5"):
            width = 5 if parts[i + 1] == "2" else 3
            yield "fixed", ";".join(parts[i : i + width])
            i += width
            continue
        if p.isdigit():
            n = int(p)
            if 30 <= n <= 37:
                yield "fg", n - 30
            elif 90 <= n <= 97:
                yield "fg", n - 82
        i += 1


def check_fixed_and_sgr(name, content):
    for number, line in enumerate(content.splitlines(), 1):
        where = "{}:{}".format(name, number)
        # A name table translates whatever name a user configures, black
        # included; only its magenta/bright-black translations are checked.
        params = [(m.group(1), False) for m in ESCAPE.finditer(line)]
        params += [(m.group(1), True) for m in SGR_TABLE.finditer(line)]
        for match, is_table in params:
            for kind, value in sgr_params(match):
                if kind == "fixed":
                    fail(where, "fixed-colour escape {} (use ANSI 30-37/90-97)".format(value))
                elif not (is_table and value == 0):
                    use_text(value, where)
        if RGB_LITERAL.search(line) and not name.startswith(".config/hypr/"):
            fail(where, "rgb() colour literal outside the Hyprland baselines")
        if TMUX_INDEX.search(line):
            fail(where, "tmux colourN index (use ANSI names)")


# --- 2. per-tool slot names ---------------------------------------------------
BASE = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
TMUX_NAMES = dict({n: i for i, n in enumerate(BASE)}, **{"bright" + n: i + 8 for i, n in enumerate(BASE)})
# ratatui (yazi): gray = 7, darkgray = 8, light* = 9-14, white = 15.
YAZI_NAMES = dict(
    {n: i for i, n in enumerate(BASE[:7])},
    gray=7,
    darkgray=8,
    white=15,
    **{"light" + n: i + 9 for i, n in enumerate(BASE[1:7])}
)
# duckdb: gray = 90 (ANSI 8), brightgray = 37 (ANSI 7), white = 97 (ANSI 15).
DUCKDB_NAMES = dict(
    {n: i for i, n in enumerate(BASE[1:7], 1)},
    brightgray=7,
    gray=8,
    white=15,
    **{"bright" + n: i + 9 for i, n in enumerate(BASE[1:7])}
)
DUCKDB_BORDERS = {"layout", "table_layout", "view_layout", "explain_layout"}
FZF_TEXT = {"fg", "fg+", "hl", "hl+", "header", "info", "pointer", "spinner", "marker", "prompt",
            "label", "query", "disabled", "preview-fg", "ghost", "nth", "list-label", "input-label",
            "header-label", "preview-label", "footer", "footer-label"}
FZF_SELECTION = {"bg+", "selected-bg"}
# A style list: inside #[...], quotes, or bare after a YAML key / whitespace.
TMUX_STYLE = re.compile(r"(?:#\[|[\"']|^|(?<=[\s:]))((?:[\w-]+=[^\s\]\"',]*#?,)*fg=[^\s\]\"']*)")
# monitor-lib.sh maps colour names to bare SGR parameters: `red) echo '1;31' ;;`.
SGR_TABLE = re.compile(r"\b\w+\)\s+echo\s+'([0-9;]+)'")


def check_tmux(name, content):
    for number, line in enumerate(content.splitlines(), 1):
        where = "{}:{}".format(name, number)
        for match in TMUX_STYLE.finditer(line):
            attrs = dict(a.split("=", 1) for a in re.split(r"#?,", match.group(1)) if "=" in a)
            fg = attrs.get("fg", "")
            slot = TMUX_NAMES.get(fg)
            if slot is None:
                continue
            # brightblack is the border tone: allowed for separator glyphs and
            # border options, where it is a line, not text.
            if slot == 8 and ("│" in line or "border" in line):
                continue
            # black text sits on a coloured bg (the loud COPY/SYNC flags).
            if slot == 0 and attrs.get("bg", "default") not in ("default", ""):
                continue
            use_text(slot, where)


def fzf_spec(value, where):
    spec = {}
    for item in value.split(","):
        if ":" not in item:
            if item not in ("16", "dark", "light", "base16", "bw"):
                fail(where, "unknown fzf base scheme '{}'".format(item))
            continue
        element, colour = item.split(":", 1)
        colour = colour.split(":")[0]
        if colour.lstrip("-").isdigit():
            slot = int(colour)
            if slot > 15:
                fail(where, "fzf {}:{} is a 256-colour index".format(element, slot))
            spec[element] = slot
    for element, slot in spec.items():
        if element in FZF_TEXT and slot >= 0:
            use_text(slot, "{} (fzf {})".format(where, element))
        if element in FZF_SELECTION and slot == 0:
            fail(where, "fzf {}:0 is the background in DMS's palette, not a selection".format(element))
    return value


def check_fzf():
    lib = (ROOT / ".config/tmux/scripts/fzf-colors.sh").read_text()
    picker = re.search(r"^PICKER_FZF_COLORS='([^']*)'", lib, re.M)
    rc = re.search(r"^--color=(\S+)", (ROOT / ".config/fzf/fzfrc").read_text(), re.M)
    if not picker or not rc:
        fail(".config/fzf", "PICKER_FZF_COLORS or the fzfrc --color line is missing")
        return
    a = fzf_spec(picker.group(1), "fzf-colors.sh")
    b = fzf_spec(rc.group(1), "fzfrc")
    if a != b:
        fail(".config/fzf/fzfrc", "--color differs from PICKER_FZF_COLORS:\n  {}\n  {}".format(b, a))


def check_yazi():
    name = ".config/yazi/theme.toml"
    for number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
        code = line.split("#")[0]
        # Text on its own coloured background (the hovered-row indicator) is a
        # pill, not text on the terminal background.
        has_bg = re.search(r"\bbg\s*=\s*\"(\w+)\"", code) is not None
        for colour in re.findall(r"\bfg\s*=\s*\"(\w+)\"", code):
            if colour not in YAZI_NAMES:
                fail("{}:{}".format(name, number), "unknown yazi colour '{}'".format(colour))
            elif not has_bg:
                use_text(YAZI_NAMES[colour], "{}:{}".format(name, number))


# Starship styles: `style = "bold cyan"` keys and inline `[text](fg:x bg:y)`.
STARSHIP_NAMES = dict(
    {n: i for i, n in enumerate(["black", "red", "green", "yellow", "blue", "purple", "cyan", "white"])},
    **{"bright-" + n: i + 8 for i, n in enumerate(["black", "red", "green", "yellow", "blue", "purple", "cyan", "white"])}
)
STARSHIP_ATTRS = {"bold", "italic", "underline", "dimmed", "inverted", "blink", "hidden", "strikethrough", "none"}
STARSHIP_STYLE = re.compile(r"\b\w*style\s*=\s*\"([^\"]*)\"|\]\(([^)$]*)\)")


def check_starship(name):
    for number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
        where = "{}:{}".format(name, number)
        for match in STARSHIP_STYLE.finditer(line.split(" #")[0]):
            tokens = (match.group(1) or match.group(2) or "").split()
            colours = [tok for tok in tokens if tok not in STARSHIP_ATTRS]
            has_bg = any(tok.startswith("bg:") for tok in colours)
            for tok in colours:
                if tok.startswith("bg:"):
                    continue
                colour = tok[3:] if tok.startswith("fg:") else tok
                if colour.isdigit():
                    if int(colour) > 15:
                        fail(where, "starship colour {} is a 256-colour index".format(colour))
                        continue
                    slot = int(colour)
                elif colour in STARSHIP_NAMES:
                    slot = STARSHIP_NAMES[colour]
                else:
                    fail(where, "unknown starship colour '{}'".format(colour))
                    continue
                if not has_bg:
                    use_text(slot, where)


def check_lazy(name):
    key = None
    for number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
        where = "{}:{}".format(name, number)
        heading = re.match(r"^\s+(\w+):\s*$", line)
        if heading:
            key = heading.group(1)
            continue
        item = re.match(r"^\s+-\s+(\w+)\s*$", line)
        if not item or not key:
            continue
        colour = item.group(1)
        if colour == "magenta":
            fail(where, "{}: magenta is ANSI 5".format(key))
        if key.endswith("SelectedLineBgColor") or key == "selectedLineBgColor":
            if colour == "black":
                fail(where, "{}: black is the background in DMS's palette".format(key))
        elif not key.endswith("BgColor") and not key.endswith("BorderColor") and colour in BASE:
            use_text(BASE.index(colour), where)


def check_duckdb():
    name = ".duckdbrc"
    for number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
        where = "{}:{}".format(name, number)
        match = re.match(r"^\.highlight_colors\s+(\w+)\s+(\w+)", line)
        if not match:
            continue
        element, colour = match.groups()
        if colour not in DUCKDB_NAMES:
            fail(where, "'{}' is a duckdb 256-colour name or ANSI 0/5".format(colour))
        elif element not in DUCKDB_BORDERS:
            use_text(DUCKDB_NAMES[colour], where)


# --- 3. contrast against the fixture palettes ----------------------------------
def palette(path):
    colours = {}
    for line in path.read_text().splitlines():
        match = re.match(r"^\s*(color\d+|background|foreground)\s+#([0-9a-fA-F]{6})\b", line)
        if match:
            colours[match.group(1)] = match.group(2)
    return colours


def luminance(hex6):
    def linear(c):
        c = int(c, 16) / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * linear(hex6[0:2]) + 0.7152 * linear(hex6[2:4]) + 0.0722 * linear(hex6[4:6])


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def check_contrast():
    fixtures = [
        ("Catppuccin Mocha", ROOT / ".config/kitty/current-theme.conf", range(1, 16)),
        ("DMS dark", ROOT / "tests/fixtures/palettes/dms-dark.conf", range(1, 16)),
        ("DMS light", ROOT / "tests/fixtures/palettes/dms-light.conf", range(1, 8)),
    ]
    for label, path, checked in fixtures:
        colours = palette(path)
        background = colours["background"]
        for slot, where in sorted(TEXT_SLOTS):
            if slot not in checked:
                continue
            ratio = contrast(colours["color{}".format(slot)], background)
            if ratio < 4.5:
                fail(where, "ANSI {} is {:.2f}:1 on the {} background".format(slot, ratio, label))


def main():
    for name, content in tracked_files():
        check_fixed_and_sgr(name, content)
        if name == ".tmux.conf" or name.startswith(".config/tmux/"):
            check_tmux(name, content)
    check_fzf()
    check_yazi()
    check_lazy(".config/lazygit/config.yml")
    check_lazy(".config/lazydocker/config.yml")
    check_duckdb()
    for name in (".config/starship.toml", ".config/starship-plain.toml"):
        if (ROOT / name).is_file():
            check_starship(name)
    check_contrast()
    if FAILURES:
        sys.exit("ANSI slot contract violations:\n" + "\n".join(sorted(set(FAILURES))))
    print("palette contract: OK ({} text slot uses checked)".format(len(TEXT_SLOTS)))


main()
