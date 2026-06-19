# nxvim-tree

A fast, dockable, fully-featured **file explorer** for
[nxvim](https://github.com/davidrios/nxvim) — the official tree.

It is built entirely on the native `nx.*` plugin API (ADR 0002): no buffer-mutation
hacks, no bespoke rendering loop. The tree's lines are owned by a read-only
[`nx.view`](https://github.com/davidrios/nxvim) surface, the filesystem work goes
through the promise `nx.fs` API (with a recursive watch for live refresh), files open
in the **main editor** via `nx.open`, and every glyph / guide / git sign is an
extmark. That's the point: a real explorer, written the way a plugin author would
write it.

```
 ~/code/sample
 󰜺 src/
 ├ 󰏗 lib.rs
 └ 󰏗 main.rs
 󰈙 Cargo.toml
 󰍔 notes.md
 󰈙 readme.txt
```

## Features

- **Lazy, watched tree** — directories scandir on first expand; an `nx.fs` recursive
  watch auto-refreshes on disk changes (toggle with `watch`).
- **Open anywhere** — `<CR>`/`o` opens in the main window; `s`/`v`/`t` in a
  split / vsplit / tab.
- **Full file ops** — create (`a`), rename (`r`), delete (`d`, confirmed), cut (`x`),
  copy (`c`), paste (`p`), yank path (`y`).
- **Navigation** — expand/collapse (`l`/`h`), expand-all/collapse-all (`E`/`W`),
  jump to parent (`P`), change root in/out (`>`/`<`), reveal the current file (`f`).
- **Name filter** — `/` narrows to matches and their ancestors; `<Esc>` clears.
- **Icons** — Nerd-Font glyphs per extension/filename, with an ASCII fallback
  (`icons = false`) for plain terminals.
- **Git status** (opt-in) — `git = true` colours changed entries and marks dirty
  directories, refreshed on save.
- **Follow** (opt-in) — `follow = true` keeps the tree cursor on the file you're
  editing.
- **Extensible** — custom icons, per-node decorators, rebindable/added keys, and an
  `on_attach` hook (see [Extending](#extending)).

## Install

Declare it with the built-in `:Plugins` manager in your `init.lua`:

```lua
nx.plugins({
  {
    "davidrios/nxvim-tree",
    config = function()
      require("nxvim-tree").setup({})
    end,
  },
})
```

Then run `:PluginSync` to clone it, and press `<leader>e` (or run `:NxvimTree`).

## Configuration

`setup()` takes an optional table; the defaults are:

```lua
require("nxvim-tree").setup({
  root = nil,            -- tree root path (default: the editor's cwd at first open)
  position = "left",     -- dock side: "left" | "right"
  width = 32,            -- sidebar columns
  hidden = false,        -- show dotfiles?
  watch = true,          -- auto-refresh on filesystem changes
  follow = false,        -- reveal the active file as you switch buffers
  git = false,           -- colour entries by git status
  dirs_first = true,     -- sort directories ahead of files
  icons = true,          -- Nerd-Font glyphs (false → ASCII markers)
  toggle_key = "<leader>e", -- global toggle keymap (false to skip)
  open_on_start = false, -- open the tree as soon as setup() runs
  mappings = { ... },    -- key → action (see below)
  highlights = {},       -- highlight-group overrides
  icon_overrides = {},   -- extra icons, merged into the registry
  on_attach = nil,       -- fn(api, bufnr): run once the tree buffer exists
})
```

`setup()` is re-runnable — calling it again is a full reconfigure (merged fresh from
the defaults), re-applying config, highlights, and commands without mounting a second
tree.

### Commands

| Command             | Action                                  |
| ------------------- | --------------------------------------- |
| `:NxvimTree`        | toggle the sidebar                      |
| `:NxvimTreeOpen`    | open + focus the sidebar                |
| `:NxvimTreeClose`   | hide the sidebar                        |
| `:NxvimTreeRefresh` | re-scan the whole tree                  |
| `:NxvimTreeReveal`  | reveal the file in the current window   |

### Key bindings

All bindings are buffer-local on the tree and fully configurable through
`opts.mappings` — a `key → action` table. A value is a built-in action name (below),
a function `fn(tree, api)` for a custom action, or `false` to disable a default:

```lua
require("nxvim-tree").setup({
  mappings = {
    ["."] = "change_root", -- add a binding
    s = false,             -- disable the default split-open
    ["g?"] = function(_tree, api) api.reveal() end, -- a custom action
  },
})
```

| Key       | Action          | Key   | Action            |
| --------- | --------------- | ----- | ----------------- |
| `<CR>`/`o`| `select`        | `a`   | `create`          |
| `l`       | `expand`        | `r`   | `rename`          |
| `h`       | `collapse`      | `d`   | `delete`          |
| `s`       | `open_split`    | `x`   | `cut`             |
| `v`       | `open_vsplit`   | `c`   | `copy`            |
| `t`       | `open_tab`      | `p`   | `paste`           |
| `E`       | `expand_all`    | `y`   | `yank_path`       |
| `W`       | `collapse_all`  | `R`   | `refresh`         |
| `P`       | `parent`        | `H`   | `toggle_hidden`   |
| `>`       | `change_root`   | `f`   | `reveal`          |
| `<`       | `up_root`       | `/`   | `filter`          |
| `q`       | `close`         | `<Esc>` | `clear_filter`  |

The full list of action names is `require("nxvim-tree.config").ACTIONS`.

## Extending

The plugin is built to be extended without forking it.

**Custom icons** — extend the extension/filename registry:

```lua
require("nxvim-tree").register_icons({
  conf = { glyph = "\u{e615}", hl = "NxTreeIconDefault" },
  name = { [".env"] = { glyph = "\u{f462}", hl = "NxTreeIconText" } },
})
```

**Decorators** — add a sign / highlight / virtual-text per node. A decorator is
`fn(node) -> { sign_text=, sign_hl=, hl=, virt_text= }` (or `nil`). The built-in git
module is just a decorator:

```lua
require("nxvim-tree").register_decorator(function(node)
  if node.name == "TODO.md" then
    return { virt_text = { { "  ←", "WarningMsg" } } }
  end
end)
```

**Custom actions** — bind a key to `fn(tree, api)`, run inside the async
error-surfacing wrapper (so it can `nx.await` freely):

```lua
require("nxvim-tree").register_action("gx", function(_tree, api)
  local node = api.node()       -- the node under the cursor
  if node then nx.ui.open(node.path) end
end)
```

`api` exposes `render(opts)`, `run(body)`, `reveal(path)`, `refresh()`, `close()`,
`set_root(path)`, `register_decorator(fn)`, `root()`, `state()` (the tree) and
`node()` (the node under the cursor).

**`on_attach`** — run once when the tree buffer exists (for buffer-scoped maps /
options): `on_attach = function(api, bufnr) ... end`.

### Highlights

The explorer uses the **canonical `NvimTree*` highlight group names** from
nvim-tree.lua — so a ported colorscheme that already styles those groups (e.g.
[catppuccin](https://github.com/catppuccin)'s nvim-tree integration) themes the tree
**unmodified**. The groups are:

| Group                       | What it colors                         |
| --------------------------- | -------------------------------------- |
| `NvimTreeRootFolder`        | the root header line                   |
| `NvimTreeFolderName`        | a closed directory name                |
| `NvimTreeOpenedFolderName`  | an expanded directory name             |
| `NvimTreeEmptyFolderName`   | a directory with no children           |
| `NvimTreeFolderIcon`        | the folder glyph                       |
| `NvimTreeIndentMarker`      | the tree guide lines                   |
| `NvimTreeSymlink`           | a symlink name                         |
| `NvimTreeOpenedFile`        | a file currently open in a buffer      |
| `NvimTreeSpecialFile`       | README / Makefile / Cargo.toml …       |
| `NvimTreeImageFile`         | image files                            |
| `NvimTreeCutHL` / `…CopiedHL` | a node marked for move / copy        |
| `NvimTreeLiveFilterValue`   | the active `/filter` tag               |
| `NvimTreeGitNew` / `…Dirty` / `…Staged` / `…Deleted` | git status |

A plain file's name is left unhighlighted so it inherits the window's `Normal`,
exactly as in nvim-tree. These groups are defined only as a **fallback** — a
colorscheme (or your `opts.highlights` override) that defines them wins, regardless
of load order:

```lua
require("nxvim-tree").setup({
  highlights = { NvimTreeRootFolder = { fg = "#f9e2af", bold = true } },
})
```

Per-extension **icon colors** have no NvimTree equivalent (nvim-tree colors icons via
nvim-web-devicons), so those live under the plugin's own `NxTreeIcon*` namespace and
can likewise be overridden.

## Trying it locally

This repo ships a runnable demo:

```sh
NXVIM_CONFIG=examples cargo run -p nxvim -- examples/sample/readme.txt
```

(run from a checkout that sits next to your nxvim checkout — see `examples/init.lua`).

## Tests

The plugin carries a Lua test suite (`test/*_spec.lua`) built on nxvim's native
`nx.test` framework — pure-Lua tests that drive a real editor over a temp filesystem.
Run them headlessly:

```sh
nxvim --test-plugin .
```

The suite covers the config merge/validation, the model (lazy load, sort, hidden
filter, refresh identity), icon and git classification, and the end-to-end flows
(render, expand/collapse, hidden toggle, filter, create, delete, open, change-root)
driven with real keys.

## License

MIT © David Rios
