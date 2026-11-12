import functools
import json
import subprocess
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
YAZI = ROOT / ".config/yazi/theme.toml"
NEO_TREE = ROOT / ".config/nvim/lua/plugins/neo-tree.lua"
HELPER = ROOT / "tests/helpers/inspect_neo_tree_config.lua"

EXPECTED_GROUPS = {
    "󰝰": ["src"],
    "󰉓": ["components", "component", "vendor", "modules", "packages"],
    "󱂷": ["context", "types", "docs", "examples"],
    "󱋣": ["models", "schema", "schemas", "store", "stores", "database", "db", "data", "redis"],
    "󱞊": ["views", ".storybook"],
    "󰉒": ["controllers", "services", "service", "providers"],
    "󰾶": ["middleware"],
    "󰣞": ["js", "javascript", "ts", "typescript", "react", "vue", "angular", "svelte", "node", "nodejs", "python", "rust", "go", "golang", "java", "kotlin", "php", "ruby", "swift", "dart", "flutter", "elixir", "scala", "lua", "graphql"],
    "󰡰": ["api", "docker", "kubernetes", "k8s", "terraform", "ansible", "aws", "azure", "gcp", "nginx", ".docker", "server", "cloud"],
    "󰲂": ["lib", "core", "common"],
    "󱧼": ["utils", "util", "helpers", "build", "dist", "out", "target"],
    "󱂵": ["app", "apps", ".nuxt"],
    "󰉋": ["layouts", "fonts", "font", "styles", "css", "scss", "sass", "nvim", ".next", ".expo"],
    "󱧶": ["pages", "scripts"],
    "󱧰": ["public", "static", ".vercel"],
    "󰚝": ["themes", "theme"],
    "󰉏": ["assets", "images", "img", "icons"],
    "󱁿": ["config", "configs", "settings", ".vscode", ".idea", ".config"],
    "󱁽": ["constants", "bin"],
    "󰴋": ["ci", "workflows", ".github", ".gitlab", ".git", "hooks", ".husky", "migrations"],
    "󰢬": ["keys", "certs"],
    "󰉐": ["secrets"],
    "󱉭": ["i18n", "locales", "lang", "translations"],
    "󰉗": ["plugins"],
    "󱥾": ["coverage", "test", "tests", "spec"],
    "󰥨": ["logs"],
    "󰪺": ["tmp", "temp", "cache", ".cache"],
    "󰛫": ["backup"],
    "󰉍": ["deps", "node_modules"],
    "󰉌": [".local"],
    "󱧊": ["mocks"],
    "󱧺": ["media", "videos"],
    "󱍙": ["audio"],
    "󰉙": ["seeders"],
}


# ratatui colour names (yazi) -> ANSI slot: gray = 7, darkgray = 8, white = 15.
YAZI_SLOTS = {
    "black": 0, "red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6, "gray": 7,
    "darkgray": 8, "lightred": 9, "lightgreen": 10, "lightyellow": 11, "lightblue": 12,
    "lightmagenta": 13, "lightcyan": 14, "white": 15,
}


def expected_icons():
    return {name: glyph for glyph, names in EXPECTED_GROUPS.items() for name in names}


def parse_yazi_prepend_dirs(theme):
    return [(entry["name"], entry["text"]) for entry in theme["icon"]["prepend_dirs"]]


def load_yazi():
    return tomllib.loads(YAZI.read_text(encoding="utf-8"))


@functools.cache
def inspect_neo_tree():
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", str(HELPER), str(NEO_TREE)],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    # Neovim 0.11 emits :print output on stderr in headless `-l` mode.
    output = (result.stdout + "\n" + result.stderr).strip()
    return json.loads(output.splitlines()[-1])


class MaterialFolderIconsTest(unittest.TestCase):
    def test_yazi_and_neo_tree_named_directory_glyphs_match(self):
        expected = expected_icons()
        self.assertEqual(140, len(expected))

        yazi_theme = tomllib.loads(YAZI.read_text(encoding="utf-8"))
        yazi_entries = parse_yazi_prepend_dirs(yazi_theme)

        self.assertEqual(140, len(yazi_entries))
        self.assertEqual(140, len({name for name, _ in yazi_entries}))

        self.assertEqual(expected, dict(yazi_entries))
        self.assertEqual(expected, inspect_neo_tree()["directory_glyphs"])

    def test_yazi_named_directory_colours_are_neo_trees_slots(self):
        # neo-tree resolves each mini.icons group to one ANSI slot through kitty's
        # palette (customize/tree_colors.lua); yazi must name that same slot.
        config = inspect_neo_tree()
        slots = config["tree_colors"]["icons"]
        yazi = {entry["name"]: entry["fg"] for entry in load_yazi()["icon"]["prepend_dirs"]}
        self.assertEqual(set(slots), set(config["directory_hls"].values()))
        for name, group in config["directory_hls"].items():
            with self.subTest(directory=name, group=group):
                self.assertEqual(slots[group], YAZI_SLOTS[yazi[name]])

    def test_yazi_plain_folders_are_neo_trees_directory_slot_and_glyph(self):
        config = inspect_neo_tree()
        directory = config["tree_colors"]["directory"]
        theme = load_yazi()
        dir_conds = [c for c in theme["icon"].get("prepend_conds", []) if "dir" in c["if"]]
        # Without it yazi falls back to the preset's fixed, palette-blind colour.
        self.assertEqual(1, len(dir_conds), "yazi needs exactly one dir icon in [icon] prepend_conds")
        self.assertEqual({"if", "text", "fg"}, set(dir_conds[0]))
        self.assertEqual("dir", dir_conds[0]["if"])
        self.assertEqual(config["folder_closed"], dir_conds[0]["text"])
        self.assertEqual(directory, YAZI_SLOTS[dir_conds[0]["fg"]])
        # The folder-name rule: the first plain `*/` rule decides every folder name.
        names = [r for r in theme["filetype"]["rules"] if r.get("url") == "*/" and "is" not in r]
        self.assertEqual(directory, YAZI_SLOTS[names[0]["fg"]])

    def test_yazi_hovered_row_is_neo_trees_current_row(self):
        cursor = inspect_neo_tree()["tree_colors"]["cursor"]
        indicator = load_yazi()["indicator"]
        for row in ("parent", "current"):
            with self.subTest(row=row):
                self.assertEqual(cursor["fg"], YAZI_SLOTS[indicator[row]["fg"]])
                self.assertEqual(cursor["bg"], YAZI_SLOTS[indicator[row]["bg"]])
        self.assertEqual(cursor["bold"], indicator["current"].get("bold", False))

    def test_neo_tree_runtime_configuration_is_single_and_preserves_options(self):
        config = inspect_neo_tree()
        self.assertEqual(1, config["setup_count"])
        self.assertEqual("preserved", config["sentinel"])
        self.assertEqual(1, config["incoming_handler_count"])
        self.assertTrue(config["incoming_unchanged"])
        self.assertEqual(config["incoming_before"], config["incoming_after"])
        self.assertEqual(3, config["final_handler_count"])
        self.assertEqual("󰉋", config["folder_closed"])
        self.assertEqual("󰝰", config["folder_open"])
        self.assertEqual("󰉖", config["folder_empty"])
        self.assertEqual("󰷏", config["folder_empty_open"])
        shared = config["shared_diagnostics"]
        self.assertEqual({"error": shared["Error"], "warn": shared["Warn"],
                          "info": shared["Info"], "hint": shared["Hint"]}, config["diagnostics"])

    def test_neo_tree_does_not_globally_configure_diagnostics_and_is_valid_lua(self):
        self.assertEqual(0, inspect_neo_tree()["diagnostic_config_calls"])
        subprocess.run(["luac", "-p", str(NEO_TREE)], cwd=ROOT, check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
