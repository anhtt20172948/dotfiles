# Material Folder Icons Design

## Goal

Make Yazi and Neo-tree render a consistent, maintainable set of named directory
icons using only folder-shaped Material Design glyphs from Nerd Fonts.

## Scope

- Update `.config/yazi/theme.toml` and
  `.config/nvim/lua/plugins/neo-tree.lua`.
- Preserve the existing named-directory coverage and Catppuccin Mocha color
  semantics.
- Add explicit `.local` and `nvim` mappings so the two applications have the
  same runtime behavior for directories present in this repository.
- Fix the related Neo-tree diagnostic-icon, empty-folder padding, and duplicate
  `setup()` issues found during review.
- Add a small regression test for the icon configuration.
- Do not redesign unrelated Neo-tree mappings, renderers, filters, or window
  behavior.

The optional `.theme` and `.nvimlog` file-icon overrides are not part of this
directory-icon change. File icons remain owned by Yazi defaults and
`nvim-web-devicons`.

## Icon Policy

Every named directory icon must come from this reviewed folder-shaped subset of
the Material Design Icons packaged by Nerd Fonts and used by `mini.icons`:

| Role | Glyph | Intended use |
| --- | --- | --- |
| Source | `󰴉` | source, language, framework, and API directories |
| Library | `󰲂` | libraries, shared code, vendor code |
| Application | `󰉗` | apps and user-facing application structure |
| Generic | `󰉋` | folders without a stronger category |
| Images | `󰉏` | images, assets, icons, and fonts |
| Configuration | `󱁿` | configuration, settings, CI, and infrastructure |
| Documentation | `󱂷` | documentation, examples, pages, and translations |
| Runtime | `󱁽` | plugins, hooks, modules, and editor runtime content |
| Cache | `󰪺` | cache, temporary, logs, backup, and coverage output |
| Build/System | `󱧼` | build output, servers, cloud, and deployment targets |
| Package/Binary | `󱧺` | packages, dependencies, binaries, and node modules |
| Local/User | `󰉌` | local user data such as `.local` |
| Test/Media | `󱞊` | tests, mocks, video, audio, and media |
| Data/Templates | `󱋣` | databases, schemas, stores, and migrations |
| Open | `󰝰` | expanded or hovered generic directories |
| Empty | `󰉖` | closed empty directories |
| Empty open | `󰷏` | expanded empty directories |

No language logo, service logo, standalone cog, database cylinder, document,
media, key, or other non-folder silhouette may appear in a directory mapping.
Color remains the secondary semantic channel and continues to use the existing
Catppuccin Mocha palette in Yazi and corresponding `MiniIcons*` highlight groups
in Neovim.

## Configuration Design

### Shared mapping behavior

The explicit Yazi and `mini.icons` directory tables remain parallel because the
two applications consume different configuration languages. A regression test
will parse both files and assert identical directory names and glyphs. This
avoids adding a runtime generator or a new configuration dependency.

The mapping grows from 138 to 140 entries by adding `.local` and `nvim`.
Neo-tree may still use `mini.icons` built-ins for names outside the explicit
table, but every directory present in this repository that resolves to a
non-default built-in icon must also be explicit in Yazi.

### Yazi

- Keep `[flavor].dark = "catppuccin-mocha"`.
- Keep `[icon].prepend_dirs`, which is the correct override mechanism when a
  flavor is active.
- Add `prepend_conds` fallbacks for generic closed and hovered directories so
  the active flavor's Seti folder glyphs cannot reintroduce non-Material icons.
- Replace every non-folder glyph with a glyph from the approved table.
- Update the comment to say "Material Design folder glyphs in Nerd Fonts PUA";
  do not claim all code points are in `U+F0xxx`.

### Neo-tree

- Configure the same 140 names through `mini.icons`.
- Keep the provider behavior for named directories and file icons.
- Use Material glyphs for all generic folder states: closed `󰉋`, open `󰝰`,
  empty `󰉖`, and empty-open `󰷏`. Do not embed padding because Neo-tree supplies
  component padding itself.
- Move diagnostic symbols into
  `default_component_configs.diagnostics.symbols` so Neo-tree does not mutate
  the global Neovim diagnostic configuration or conflict with LSP settings.
- Build one immutable final configuration table from Lazy's `opts`, the local
  Neo-tree settings, and the move/rename event handlers, then call
  `require("neo-tree").setup()` exactly once.

## Validation

The regression test will fail before implementation because the current files
contain non-folder glyphs and omit `.local` and `nvim`. After implementation it
must verify:

1. Both files parse successfully.
2. Both explicit directory tables contain the same 140 unique names.
3. Corresponding names use identical glyphs.
4. Every glyph belongs to the approved folder-shaped allowlist.
5. `.local` and `nvim` are explicit and synchronized.
6. Yazi and Neo-tree generic closed/open/empty folder states use the approved
   Material glyphs with no embedded padding.
7. Neo-tree does not call global `vim.diagnostic.config()`.
8. Neo-tree contains exactly one `require("neo-tree").setup()` call.

Runtime checks will additionally load the Yazi theme, initialize the configured
`mini.icons` table in headless Neovim, and confirm all explicit mappings resolve
without falling back to the generic icon.

## Risks and Mitigations

- **Glyph availability:** use only glyphs already shipped by the installed Nerd
  Fonts and present in the pinned `mini.icons` implementation.
- **Cross-application drift:** keep a permanent parser-based equality test.
- **Lost Neo-tree options:** merge Lazy's incoming `opts` into a new table before
  the single setup call and test the resulting Lua syntax/runtime load.
- **Reduced semantic detail:** retain category-specific folder silhouettes and
  the existing color taxonomy instead of using one generic folder everywhere.
