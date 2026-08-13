# Material Folder Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Yazi and Neo-tree folder icon use synchronized, folder-shaped Material Design glyphs while fixing the related Neo-tree setup, diagnostics, and padding defects.

**Architecture:** Keep the two application-native mapping tables because Yazi consumes TOML and `mini.icons` consumes Lua. Protect them from drift with a standard-library Python regression test and a small headless-Neovim inspector that verifies the final configuration passed to Neo-tree.

**Tech Stack:** Python 3 `unittest`/`tomllib`, Lua, Neovim 0.11, `mini.icons`, Neo-tree v3.x, Yazi 26.x.

## Global Constraints

- Preserve the current 138 named-directory entries and add exactly `.local` and `nvim`, producing 140 unique names.
- Directory mappings may use only the 14 approved named-folder glyphs in the design spec.
- Generic state icons must be Material glyphs: closed `󰉋`, open/hovered `󰝰`, empty `󰉖`, empty-open `󰷏`.
- Preserve existing Catppuccin Mocha colors and corresponding `MiniIcons*` highlights.
- Do not change file icons, unrelated Neo-tree renderers, filters, mappings, or window behavior.
- Do not mutate Lazy's incoming `opts` table or its `event_handlers` list.
- Call `require("neo-tree").setup()` exactly once.
- The worktree already contains user changes in both target files; preserve them and do not commit without explicit user approval.

---

### Task 1: Add Regression Coverage

**Files:**
- Create: `tests/test_material_folder_icons.py`
- Create: `tests/helpers/inspect_neo_tree_config.lua`

**Interfaces:**
- Consumes: `.config/yazi/theme.toml` and `.config/nvim/lua/plugins/neo-tree.lua`.
- Produces: `python3 -m unittest tests.test_material_folder_icons -v`, the permanent drift and configuration regression test.

- [ ] **Step 1: Create the headless-Neovim inspector**

```lua
local plugin_path = assert(arg[1], "neo-tree plugin path is required")
local setup_calls = {}

package.preload["neo-tree"] = function()
	return {
		setup = function(config)
			table.insert(setup_calls, config)
		end,
	}
end

package.preload["neo-tree.events"] = function()
	return { FILE_MOVED = "file_moved", FILE_RENAMED = "file_renamed" }
end

Snacks = { rename = { on_rename_file = function() end } }

local specs = assert(loadfile(plugin_path))()
local incoming = {
	sentinel = "preserved",
	event_handlers = { { event = "existing", handler = function() end } },
}
specs[2].config(nil, incoming)

local config = assert(setup_calls[1], "neo-tree setup was not called")
print(vim.json.encode({
	setup_count = #setup_calls,
	sentinel = config.sentinel,
	incoming_handler_count = #incoming.event_handlers,
	final_handler_count = #(config.event_handlers or {}),
	folder_closed = config.default_component_configs.icon.folder_closed,
	folder_open = config.default_component_configs.icon.folder_open,
	folder_empty = config.default_component_configs.icon.folder_empty,
	folder_empty_open = config.default_component_configs.icon.folder_empty_open,
	diagnostics = config.default_component_configs.diagnostics.symbols,
}))
```

- [ ] **Step 2: Create the Python regression test**

The test must define these exact name groups and expected glyphs:

```python
EXPECTED_GROUPS = {
    "󰴉": "src components component context types models views controllers services service middleware providers js javascript ts typescript react vue angular svelte node nodejs python rust go golang java kotlin php ruby swift dart flutter elixir scala lua graphql api".split(),
    "󰲂": "lib core common utils util helpers vendor".split(),
    "󰉗": "app apps layouts pages public static".split(),
    "󰉋": "fonts font styles css scss sass themes theme nvim".split(),
    "󰉏": "assets images img icons".split(),
    "󱁿": "config configs settings constants docker kubernetes k8s terraform ansible aws azure gcp nginx ci workflows keys certs secrets .github .gitlab .git .vscode .idea .docker .vercel .config".split(),
    "󱂷": "docs examples i18n locales lang translations".split(),
    "󱁽": "hooks plugins modules scripts .husky .storybook .next .nuxt .expo".split(),
    "󰪺": "coverage logs tmp temp cache backup .cache".split(),
    "󱧼": "build dist out target server cloud".split(),
    "󱧺": "packages deps bin node_modules".split(),
    "󰉌": [".local"],
    "󱞊": "test tests spec mocks media videos audio".split(),
    "󱋣": "schema schemas store stores database db data redis migrations seeders".split(),
}
```

Implement tests using `tomllib.loads()` for Yazi and a strict line regex for the
Lua `directory` table. Assert:

```python
self.assertEqual(140, len(expected))
self.assertEqual(expected, yazi_icons)
self.assertEqual(expected, neo_tree_icons)
self.assertEqual(
    [
        {"if": "dir & hovered", "text": "󰝰", "fg": "#89b4fa"},
        {"if": "dir", "text": "󰉋", "fg": "#89b4fa"},
    ],
    yazi_theme["icon"]["prepend_conds"],
)
```

Run the Lua inspector with:

```python
subprocess.run(
    ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l",
     str(HELPER), str(NEO_TREE)],
    cwd=ROOT, check=True, text=True, capture_output=True,
)
```

Assert setup count `1`, incoming sentinel preserved, incoming handler count still
`1`, final handler count `3`, the four Material state glyphs, and diagnostic
symbols `{error = "", warn = "", info = "", hint = "󰌵"}`. Also assert the
source contains no `vim.diagnostic.config(` call and passes `luac -p`.

- [ ] **Step 3: Run the tests and verify RED**

Run:

```bash
python3 -m unittest tests.test_material_folder_icons -v
```

Expected: failures showing 138 rather than 140 names, non-folder glyphs,
missing Yazi Material fallback conditions, two setup calls, global diagnostic
configuration, and padded/non-Material empty-folder state.

### Task 2: Synchronize the Material Folder Mappings

**Files:**
- Modify: `.config/yazi/theme.toml:4-149`
- Modify: `.config/nvim/lua/plugins/neo-tree.lua:16-158`
- Test: `tests/test_material_folder_icons.py`

**Interfaces:**
- Consumes: `EXPECTED_GROUPS` from Task 1 and the approved design specification.
- Produces: two identical 140-entry name-to-glyph maps.

- [ ] **Step 1: Update Yazi mappings**

Keep every existing `name` and `fg`. Change only `text` according to
`EXPECTED_GROUPS`, add:

```toml
{ name = ".local", text = "󰉌", fg = "#94e2d5" },
{ name = "nvim", text = "󰉋", fg = "#a6e3a1" },
```

Update the header comment to "Material Design folder glyphs in Nerd Fonts PUA"
and add generic Material fallbacks after `prepend_dirs`:

```toml
prepend_conds = [
  { if = "dir & hovered", text = "󰝰", fg = "#89b4fa" },
  { if = "dir", text = "󰉋", fg = "#89b4fa" },
]
```

- [ ] **Step 2: Update `mini.icons` mappings**

Keep every existing name and `hl`. Change only `glyph` according to
`EXPECTED_GROUPS`, then add:

```lua
[".local"] = { glyph = "󰉌", hl = "MiniIconsCyan" },
nvim = { glyph = "󰉋", hl = "MiniIconsGreen" },
```

- [ ] **Step 3: Run mapping tests and verify GREEN for synchronization**

Run:

```bash
python3 -m unittest tests.test_material_folder_icons.MaterialFolderIconTests.test_named_mappings -v
python3 -m unittest tests.test_material_folder_icons.MaterialFolderIconTests.test_yazi_fallbacks -v
```

Expected: both tests pass with 140 unique synchronized mappings.

### Task 3: Make Neo-tree Configuration Single-Setup and Isolated

**Files:**
- Modify: `.config/nvim/lua/plugins/neo-tree.lua:203-740`
- Test: `tests/helpers/inspect_neo_tree_config.lua`
- Test: `tests/test_material_folder_icons.py`

**Interfaces:**
- Consumes: Lazy's optional `opts` table.
- Produces: a new final options table passed once to `neo-tree.setup`, without mutating `opts`.

- [ ] **Step 1: Remove the global diagnostic mutation**

Delete the `vim.diagnostic.config({...})` block and its obsolete version
comments. Add under `default_component_configs`:

```lua
diagnostics = {
	symbols = {
		error = "",
		warn = "",
		info = "",
		hint = "󰌵",
	},
},
```

- [ ] **Step 2: Use Material glyphs for every generic Neo-tree folder state**

```lua
folder_closed = "󰉋",
folder_open = "󰝰",
folder_empty = "󰉖",
folder_empty_open = "󰷏",
```

- [ ] **Step 3: Merge into an immutable final configuration and setup once**

Convert the large second setup argument into `local local_opts = { ... }`.
Replace the earlier handler mutation/setup and the later setup call with:

```lua
local move_handlers = {
	{ event = events.FILE_MOVED, handler = on_move },
	{ event = events.FILE_RENAMED, handler = on_move },
}
local incoming_opts = opts or {}
local merged_handlers = vim.list_extend(
	vim.deepcopy(incoming_opts.event_handlers or {}),
	move_handlers
)
local final_opts = vim.tbl_deep_extend("force", {}, incoming_opts, local_opts)
final_opts.event_handlers = merged_handlers
require("neo-tree").setup(final_opts)
```

Place this after `local_opts` is complete and before the existing autocmd/keymap
registration. Do not mutate `incoming_opts`, and do not deep-merge the handler
array by numeric index.

- [ ] **Step 4: Run configuration tests and verify GREEN**

Run:

```bash
python3 -m unittest tests.test_material_folder_icons.MaterialFolderIconTests.test_neo_tree_config -v
luac -p .config/nvim/lua/plugins/neo-tree.lua
```

Expected: one setup call, three final handlers, unchanged incoming list, retained
sentinel, Neo-tree-local diagnostics, and four Material state glyphs.

### Task 4: Full Runtime Verification and Review

**Files:**
- Verify: `.config/yazi/theme.toml`
- Verify: `.config/nvim/lua/plugins/neo-tree.lua`
- Verify: `tests/test_material_folder_icons.py`
- Verify: `tests/helpers/inspect_neo_tree_config.lua`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: verified, review-ready local changes.

- [ ] **Step 1: Run the complete regression suite**

```bash
python3 -m unittest tests.test_material_folder_icons -v
```

Expected: all tests pass.

- [ ] **Step 2: Validate the real programs and pinned icon API**

```bash
python3 -c 'import tomllib; tomllib.load(open(".config/yazi/theme.toml", "rb"))'
luac -p .config/nvim/lua/plugins/neo-tree.lua
YAZI_CONFIG_HOME="$PWD/.config/yazi" yazi --debug
nvim --headless -u NONE -i NONE -n --cmd 'set runtimepath+=/home/anhtran/.local/share/nvim/lazy/mini.icons' "+lua local s=dofile('$PWD/.config/nvim/lua/plugins/neo-tree.lua'); local d=s[2].dependencies[3]; require('mini.icons').setup(d.opts); local n=0; for name,want in pairs(d.opts.directory) do local glyph,hl,fallback=require('mini.icons').get('directory',name); assert(not fallback and glyph==want.glyph and hl==want.hl,name); n=n+1 end; assert(n==140); print('validated mappings:',n)" '+qa'
```

Expected: TOML/Lua parse, Yazi reports the intended theme path, and Neovim
validates all 140 configured mappings without fallback.

- [ ] **Step 3: Review only scoped changes**

```bash
git diff --check -- .config/yazi/theme.toml .config/nvim/lua/plugins/neo-tree.lua tests docs/superpowers
git diff -- .config/yazi/theme.toml .config/nvim/lua/plugins/neo-tree.lua tests docs/superpowers
git status --short
```

Confirm no unrelated user files were edited and leave changes uncommitted unless
the user explicitly requests a commit.
