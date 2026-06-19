-- nxvim-tree.icons — the filename/extension → { glyph, hl } registry.
--
-- A pure-Lua lookup seeded with common file kinds plus the folder glyphs. `get(node,
-- cfg)` returns the glyph and its highlight group for one node; when `cfg.icons` is
-- false it falls back to ASCII markers so the tree still works on a terminal without
-- a Nerd Font. `register(map)` extends the tables at runtime — the extensibility
-- seam surfaced as `require("nxvim-tree").register_icons(...)` and as
-- `opts.icon_overrides`.
--
-- Glyphs are written as `\u{...}` escapes (Nerd-Font v3 private-use codepoints) so
-- the source is plain ASCII and survives any editor / transport that mangles raw
-- PUA bytes. Each encodes to a 3-byte UTF-8 sequence; the renderer measures them with
-- `#glyph` (byte length) so the decoration column math stays exact. The highlight
-- groups referenced here are declared in highlights.lua and defined once at setup;
-- this module never touches the editor, it only describes.

local M = {}

-- Folder glyphs (open / closed: nf-fa-folder / folder_open) and the file fallback.
local FOLDER_CLOSED = "\u{f07b}"
local FOLDER_OPEN = "\u{f07c}"
local FILE_DEFAULT = "\u{f15b}" -- nf-fa-file

-- ASCII fallbacks used when cfg.icons == false.
local ASCII = { dir_closed = "▸", dir_open = "▾", file = " " }

-- The kinds nvim-tree singles out for their own name color. `is_image` → the
-- NvimTreeImageFile group; `is_special` → NvimTreeSpecialFile. Both name-based and
-- intentionally small; extend by editing these sets.
local IMAGE_EXTS = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  bmp = true,
  webp = true,
  ico = true,
  svg = true,
}
local SPECIAL_NAMES = {
  ["Cargo.toml"] = true,
  ["Makefile"] = true,
  ["README.md"] = true,
  ["readme.md"] = true,
}

-- is_image(name) -> true when the basename looks like an image (by extension).
function M.is_image(name)
  local ext = name:match("%.([%w]+)$")
  return ext ~= nil and IMAGE_EXTS[ext:lower()] == true
end

-- is_special(name) -> true for nvim-tree's "special file" set (README/Makefile/…).
function M.is_special(name)
  return SPECIAL_NAMES[name] == true
end

M._image_exts = IMAGE_EXTS
M._special_names = SPECIAL_NAMES

-- Exact-filename lookup (highest priority).
local by_name = {
  ["Cargo.toml"] = { glyph = "\u{e7a8}", hl = "NxTreeIconRust" },
  ["Cargo.lock"] = { glyph = "\u{f023}", hl = "NxTreeIconLock" },
  ["package.json"] = { glyph = "\u{e718}", hl = "NxTreeIconJson" },
  ["package-lock.json"] = { glyph = "\u{f023}", hl = "NxTreeIconLock" },
  ["tsconfig.json"] = { glyph = "\u{e628}", hl = "NxTreeIconTs" },
  [".gitignore"] = { glyph = "\u{e702}", hl = "NxTreeIconGit" },
  [".gitattributes"] = { glyph = "\u{e702}", hl = "NxTreeIconGit" },
  [".gitmodules"] = { glyph = "\u{e702}", hl = "NxTreeIconGit" },
  ["README.md"] = { glyph = "\u{f48a}", hl = "NxTreeIconMd" },
  ["LICENSE"] = { glyph = "\u{f0219}", hl = "NxTreeIconText" },
  ["Makefile"] = { glyph = "\u{e779}", hl = "NxTreeIconDefault" },
  ["Dockerfile"] = { glyph = "\u{f308}", hl = "NxTreeIconDefault" },
}

-- Lowercased-extension lookup (second priority).
local by_ext = {
  rs = { glyph = "\u{e7a8}", hl = "NxTreeIconRust" },
  lua = { glyph = "\u{e620}", hl = "NxTreeIconLua" },
  js = { glyph = "\u{e74e}", hl = "NxTreeIconJs" },
  mjs = { glyph = "\u{e74e}", hl = "NxTreeIconJs" },
  cjs = { glyph = "\u{e74e}", hl = "NxTreeIconJs" },
  jsx = { glyph = "\u{e7ba}", hl = "NxTreeIconJs" },
  ts = { glyph = "\u{e628}", hl = "NxTreeIconTs" },
  tsx = { glyph = "\u{e7ba}", hl = "NxTreeIconTs" },
  json = { glyph = "\u{e60b}", hl = "NxTreeIconJson" },
  toml = { glyph = "\u{e6b2}", hl = "NxTreeIconToml" },
  yaml = { glyph = "\u{e6a8}", hl = "NxTreeIconToml" },
  yml = { glyph = "\u{e6a8}", hl = "NxTreeIconToml" },
  md = { glyph = "\u{f48a}", hl = "NxTreeIconMd" },
  markdown = { glyph = "\u{f48a}", hl = "NxTreeIconMd" },
  py = { glyph = "\u{e606}", hl = "NxTreeIconPy" },
  go = { glyph = "\u{e627}", hl = "NxTreeIconGo" },
  c = { glyph = "\u{e61e}", hl = "NxTreeIconC" },
  h = { glyph = "\u{f0fd}", hl = "NxTreeIconC" },
  cpp = { glyph = "\u{e61d}", hl = "NxTreeIconC" },
  hpp = { glyph = "\u{f0fd}", hl = "NxTreeIconC" },
  sh = { glyph = "\u{f489}", hl = "NxTreeIconShell" },
  bash = { glyph = "\u{f489}", hl = "NxTreeIconShell" },
  zsh = { glyph = "\u{f489}", hl = "NxTreeIconShell" },
  fish = { glyph = "\u{f489}", hl = "NxTreeIconShell" },
  html = { glyph = "\u{e736}", hl = "NxTreeIconHtml" },
  css = { glyph = "\u{e749}", hl = "NxTreeIconCss" },
  scss = { glyph = "\u{e749}", hl = "NxTreeIconCss" },
  png = { glyph = "\u{f1c5}", hl = "NxTreeIconImage" },
  jpg = { glyph = "\u{f1c5}", hl = "NxTreeIconImage" },
  jpeg = { glyph = "\u{f1c5}", hl = "NxTreeIconImage" },
  gif = { glyph = "\u{f1c5}", hl = "NxTreeIconImage" },
  svg = { glyph = "\u{f1c5}", hl = "NxTreeIconImage" },
  txt = { glyph = "\u{f15c}", hl = "NxTreeIconText" },
  lock = { glyph = "\u{f023}", hl = "NxTreeIconLock" },
}

-- get(node, cfg) -> glyph, hl_group. Directories use the open/closed folder glyph
-- keyed off `node.expanded`; files resolve by exact name then extension, else the
-- default. With `cfg.icons == false`, returns the ASCII markers (folder name color
-- still applies to directories).
function M.get(node, cfg)
  local icons_on = not cfg or cfg.icons ~= false
  if node.type == "directory" then
    if not icons_on then
      return (node.expanded and ASCII.dir_open or ASCII.dir_closed), "NvimTreeFolderIcon"
    end
    return (node.expanded and FOLDER_OPEN or FOLDER_CLOSED), "NvimTreeFolderIcon"
  end
  if not icons_on then
    return ASCII.file, "NxTreeIconDefault"
  end
  local exact = by_name[node.name]
  if exact then
    return exact.glyph, exact.hl
  end
  local ext = node.name:match("%.([%w]+)$")
  local e = ext and by_ext[ext:lower()]
  if e then
    return e.glyph, e.hl
  end
  return FILE_DEFAULT, "NxTreeIconDefault"
end

-- register(map) — extend the registry. Keys are extensions (`{ rs = { glyph=, hl= } }`);
-- a `name = { ["exact.file"] = { … } }` sub-table extends the exact-name table. The
-- highlight groups referenced must already be defined (highlights.lua) or supplied by
-- the caller via `opts.highlights`. Returns nothing.
function M.register(map)
  for k, v in pairs(map or {}) do
    if k == "name" then
      for n, spec in pairs(v) do
        by_name[n] = spec
      end
    else
      by_ext[k] = v
    end
  end
end

-- Test/introspection seam: the live tables (read-only by convention).
M._by_name = by_name
M._by_ext = by_ext

return M
