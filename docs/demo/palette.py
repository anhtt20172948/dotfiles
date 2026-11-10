#!/usr/bin/env python3
"""Turn a kitty palette file into what the demo renderer needs.

    palette.py theme   PALETTE NAME   VHS `Set Theme` JSON on stdout
    palette.py kitty   PALETTE        a dank-theme.conf body on stdout
    palette.py colors  PALETTE        "BACKGROUND FOREGROUND" as bare hex

PALETTE is a kitty colour file: .config/kitty/current-theme.conf (Catppuccin
Mocha) or a recorded DMS palette from tests/fixtures/palettes/. The kitty body
adds the cursor line DMS writes (its primary colour, which dank16 puts in
ANSI 6) when the recording has none, so Neovim takes the same accent it takes
on the workstation.
"""

import json
import re
import sys

LINE = re.compile(r"^\s*([a-z_0-9]+)\s+(#[0-9a-fA-F]{6})\s*$")
ANSI = (
    "black",
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
)


def read_palette(path: str) -> dict[str, str]:
    values = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = LINE.match(line)
            if match:
                values[match.group(1)] = match.group(2).lower()
    missing = [key for key in ("background", "foreground") if key not in values]
    missing += [f"color{i}" for i in range(16) if f"color{i}" not in values]
    if missing:
        raise SystemExit(f"{path}: missing {', '.join(missing)}")
    return values


def vhs_theme(values: dict[str, str], name: str) -> dict[str, str]:
    theme = {
        "name": name,
        "background": values["background"],
        "foreground": values["foreground"],
        # kitty's cursor, else DMS's primary (ANSI 6).
        "cursor": values.get("cursor", values["color6"]),
        # kitty.conf sets selection to none (reverse video); xterm.js needs a
        # colour, so use the surface slot the slot contract reserves for it.
        "selection": values["color8"],
    }
    for index, colour in enumerate(ANSI):
        theme[colour] = values[f"color{index}"]
        theme["bright" + colour.capitalize()] = values[f"color{index + 8}"]
    return theme


def kitty_body(path: str, values: dict[str, str]) -> str:
    with open(path, encoding="utf-8") as handle:
        body = handle.read()
    if "cursor" not in values:
        body = body.rstrip("\n") + f"\ncursor {values['color6']}\n"
    return body


def main(argv: list[str]) -> int:
    if len(argv) == 4 and argv[1] == "theme":
        print(json.dumps(vhs_theme(read_palette(argv[2]), argv[3])))
        return 0
    if len(argv) == 3 and argv[1] == "colors":
        values = read_palette(argv[2])
        print(values["background"][1:], values["foreground"][1:])
        return 0
    if len(argv) == 3 and argv[1] == "kitty":
        sys.stdout.write(kitty_body(argv[2], read_palette(argv[2])))
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
