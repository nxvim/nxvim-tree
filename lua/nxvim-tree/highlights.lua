-- nxvim-tree.highlights — the highlight palette and a fallback-only applier.
--
-- The structural / git / state groups use the canonical **NvimTree\*** names from
-- nvim-tree.lua, on purpose: a ported colorscheme that styles those names (e.g.
-- catppuccin's nvim-tree integration) themes the explorer UNMODIFIED. We only define
-- them as a FALLBACK — an explicit user override wins, and otherwise a default is
-- installed only when the group is not already defined, so a colorscheme that already
-- styles `NvimTree*` keeps its colors regardless of load order.
--
-- The per-extension *icon* colors have no NvimTree equivalent (upstream nvim-tree
-- colors icons through nvim-web-devicons, not its own groups), so those stay under
-- the plugin's own `NxTreeIcon*` namespace — a colorscheme never needs to know them,
-- and a power user can still override them.
--
-- Fallback colors are Catppuccin-Mocha values so a bare `setup()` reads well on a dark
-- background with no theme loaded. They are foreground-only (no `bg`) so applying a
-- group to a name range never paints a background strip behind the text.

local M = {}

-- name -> default spec (the `nx.hl.define` opts table).
M.defaults = {
  -- Window chrome (the sidebar's own background, cursorline, and `~` fillers) —
  -- the canonical NvimTree* names, applied through the tree window's `winhighlight`
  -- remap (`Normal:NvimTreeNormal`, …), not to a name range. The fallbacks LINK to
  -- the editor's own chrome groups so they follow the active theme's light/dark
  -- flavour (a hardcoded colour would go dark on catppuccin-latte); a colorscheme
  -- that defines these (e.g. catppuccin sets NvimTreeNormal per-flavour) still wins
  -- (see M.apply). Normal→NormalFloat gives the sidebar a distinct shade like
  -- nvim-tree; cursorline / fillers then match the editor exactly.
  NvimTreeNormal = { link = "NormalFloat" }, -- the sidebar background
  NvimTreeEndOfBuffer = { link = "EndOfBuffer" }, -- `~` fillers, themed like the editor
  NvimTreeCursorLine = { link = "CursorLine" }, -- the highlighted current row
  NvimTreeCursorLineNr = { link = "CursorLineNr" },
  -- structure (canonical NvimTree* — themed by a ported colorscheme)
  NvimTreeRootFolder = { fg = "#b4befe", bold = true }, -- the root header line
  NvimTreeFolderName = { fg = "#89b4fa" }, -- a closed directory's name
  NvimTreeOpenedFolderName = { fg = "#89b4fa", bold = true }, -- an expanded directory
  NvimTreeEmptyFolderName = { fg = "#89b4fa" }, -- a directory with no children
  NvimTreeFolderIcon = { fg = "#89b4fa" }, -- the open/closed folder glyph
  NvimTreeIndentMarker = { fg = "#6c7086" }, -- the tree guide lines
  NvimTreeSymlink = { fg = "#f5c2e7" }, -- a symlink's name
  NvimTreeOpenedFile = { fg = "#f5c2e7" }, -- a file open in a buffer
  NvimTreeSpecialFile = { fg = "#f2cdcd" }, -- README / Makefile / Cargo.toml …
  NvimTreeImageFile = { fg = "#cdd6f4" }, -- an image file
  NvimTreeCutHL = { fg = "#f38ba8", italic = true }, -- a node marked to be moved
  NvimTreeCopiedHL = { fg = "#fab387", italic = true }, -- a node marked to be copied
  NvimTreeLiveFilterValue = { fg = "#a6adc8", italic = true }, -- the active "/filter" tag
  -- git (canonical NvimTree* — used by the optional git module)
  NvimTreeGitNew = { fg = "#a6e3a1" }, -- untracked / added
  NvimTreeGitDirty = { fg = "#f9e2af" }, -- modified (and the dirty-dir dot)
  NvimTreeGitStaged = { fg = "#94e2d5" }, -- staged-only
  NvimTreeGitDeleted = { fg = "#f38ba8" }, -- deleted
  -- per-extension icon colors (plugin-private; nvim-tree colors icons via devicons)
  NxTreeIconDefault = { fg = "#9399b2" },
  NxTreeIconRust = { fg = "#fab387" },
  NxTreeIconLua = { fg = "#74c7ec" },
  NxTreeIconJs = { fg = "#f9e2af" },
  NxTreeIconTs = { fg = "#89b4fa" },
  NxTreeIconJson = { fg = "#f9e2af" },
  NxTreeIconToml = { fg = "#fab387" },
  NxTreeIconMd = { fg = "#cdd6f4" },
  NxTreeIconPy = { fg = "#f9e2af" },
  NxTreeIconGo = { fg = "#89dceb" },
  NxTreeIconC = { fg = "#89b4fa" },
  NxTreeIconShell = { fg = "#a6e3a1" },
  NxTreeIconHtml = { fg = "#fab387" },
  NxTreeIconCss = { fg = "#89b4fa" },
  NxTreeIconImage = { fg = "#f5c2e7" },
  NxTreeIconText = { fg = "#bac2de" },
  NxTreeIconGit = { fg = "#f38ba8" },
  NxTreeIconLock = { fg = "#9399b2" },
}

-- apply(overrides) — define each group as a fallback (see the module header). An
-- entry in `overrides` is applied unconditionally; an unrecognized override name is
-- still honored (a plugin may color its own extra group). Idempotent.
function M.apply(overrides)
  overrides = overrides or {}
  for name, spec in pairs(M.defaults) do
    if overrides[name] then
      nx.hl.define(0, name, overrides[name])
    elseif not nx.hl.exists(name) then
      nx.hl.define(0, name, spec)
    end
  end
  for name, spec in pairs(overrides) do
    if not M.defaults[name] then
      nx.hl.define(0, name, spec)
    end
  end
end

return M
