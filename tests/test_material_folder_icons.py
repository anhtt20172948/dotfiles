import json
import re
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


def expected_icons():
    return {name: glyph for glyph, names in EXPECTED_GROUPS.items() for name in names}


def parse_yazi_prepend_dirs(theme):
    return [(entry["name"], entry["text"]) for entry in theme["icon"]["prepend_dirs"]]


def parse_neo_tree_directory_entries(source):
    match = re.search(r"directory\s*=\s*\{(?P<body>.*?)\n\s*\},\n\s*},", source, re.DOTALL)
    if not match:
        raise AssertionError("mini.icons directory table not found")
    entries = []
    line_pattern = re.compile(
        r'^\s*(?:\["(?P<bracket>[^"]+)"\]|(?P<bare>[A-Za-z_][A-Za-z0-9_]*))\s*='
        r'\s*\{\s*glyph\s*=\s*"(?P<glyph>.*?)"\s*,\s*hl\s*='
    )
    for line in match.group("body").splitlines():
        parsed = line_pattern.match(line)
        if parsed:
            entries.append((parsed.group("bracket") or parsed.group("bare"), parsed.group("glyph")))
    return entries


class MaterialFolderIconsTest(unittest.TestCase):
    def test_yazi_and_neo_tree_named_directory_glyphs_match(self):
        expected = expected_icons()
        self.assertEqual(140, len(expected))

        yazi_theme = tomllib.loads(YAZI.read_text(encoding="utf-8"))
        yazi_entries = parse_yazi_prepend_dirs(yazi_theme)
        neo_tree_entries = parse_neo_tree_directory_entries(NEO_TREE.read_text(encoding="utf-8"))

        self.assertEqual(140, len(yazi_entries))
        self.assertEqual(140, len({name for name, _ in yazi_entries}))
        self.assertEqual(140, len(neo_tree_entries))
        self.assertEqual(140, len({name for name, _ in neo_tree_entries}))

        yazi_icons = dict(yazi_entries)
        neo_tree_icons = dict(neo_tree_entries)

        self.assertEqual(expected, yazi_icons)
        self.assertEqual(expected, neo_tree_icons)

        self.assertEqual(
            [
                {"if": "dir & hovered", "text": "󰝰", "fg": "#89b4fa"},
                {"if": "dir", "text": "󰉋", "fg": "#89b4fa"},
            ],
            yazi_theme["icon"]["prepend_conds"],
        )

    def test_neo_tree_runtime_configuration_is_single_and_preserves_options(self):
        result = subprocess.run(
            ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", str(HELPER), str(NEO_TREE)],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        # Neovim 0.11 emits :print output on stderr in headless `-l` mode.
        output = (result.stdout + "\n" + result.stderr).strip()
        config = json.loads(output.splitlines()[-1])
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
        self.assertEqual({"error": "", "warn": "", "info": "", "hint": "󰌵"}, config["diagnostics"])

    def test_neo_tree_does_not_globally_configure_diagnostics_and_is_valid_lua(self):
        source = NEO_TREE.read_text(encoding="utf-8")
        self.assertNotIn("vim.diagnostic.config(", source)
        subprocess.run(["luac", "-p", str(NEO_TREE)], cwd=ROOT, check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
