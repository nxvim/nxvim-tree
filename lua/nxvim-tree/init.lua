-- nxvim-tree — a dockable, extensible file explorer for nxvim, built entirely on the
-- native `nx.*` plugin API (ADR 0002): no buffer-mutation API, no native widget.
--
-- It composes the editor's content + filesystem primitives — `nx.view` (the
-- read-only, mountable line surface), `nx.fs` (the promise filesystem: readdir,
-- mutation, recursive watch), `nx.open(path, { where = "main" })` (open a file in the
-- MAIN editor, not the sidebar), `nx.dock` (the edge panel it lives in), `nx.ui`
-- (prompts / confirms), and extmarks (icons, guides, decorator signs). The tree's
-- lines are OWNED by the view — the plugin never mutates a buffer.
--
-- Module map (one concern each):
--   config.lua      defaults + validated merge
--   highlights.lua  the highlight palette (fallback-applied)
--   icons.lua       extension/name → glyph registry
--   model.lua       the node tree, lazy scandir-on-expand, flatten-to-visible
--   render.lua      visible nodes → view lines + extmark decoration
--   actions.lua     open / navigate / create / rename / delete / cut / copy / paste …
--   keymap.lua      install the configured bindings on the tree buffer
--   git.lua         optional git-status decorator (opt-in via `git = true`)
-- This file owns the singleton tree state, the open/close/toggle lifecycle, the
-- root-change + reveal flows, the auto-refresh watch and follow autocmd, the public
-- extensibility registries, and `setup()`.
--
-- Quick start (init.lua):
--   require("nxvim-tree").setup({ width = 32, git = true })
--   -- then <leader>e or :NxvimTree toggles the sidebar.

local config = require("nxvim-tree.config")
local highlights = require("nxvim-tree.highlights")
local icons = require("nxvim-tree.icons")
local model = require("nxvim-tree.model")
local render_mod = require("nxvim-tree.render")
local actions = require("nxvim-tree.actions")
local keymap = require("nxvim-tree.keymap")

local M = {}

-- The effective configuration (rebuilt from defaults on every setup() — see setup).
-- `_decorators` is the live decorator list the render reads; it lives on config so a
-- decorator registered before the first open still applies. `icon_overrides` /
-- `highlights` are consumed at setup time.
M.config = config.defaults()
M.config._decorators = {}

local tree = nil -- the singleton tree state, built lazily on first open
local hl_applied = false
local autocmds_wired = false

-- ----- async helper ----------------------------------------------------------

-- Run an async body (which may nx.await fs/ui promises), surfacing any rejection as a
-- notification instead of an unhandled promise error.
local function run(body)
  nx.async(body)():catch(function(e)
    local msg = type(e) == "table" and e.message or e
    nx.notify("nxvim-tree: " .. tostring(msg), 4)
  end)
end

local function render(opts)
  if tree then
    render_mod.render(tree, opts)
  end
end

-- The helper bundle handed to every action / the git module. The closures read the
-- live `tree` upvalue, so a single api object stays valid across rebuilds.
local api = {
  run = run,
  render = render,
  set_root = function(path)
    M.set_root(path)
  end,
  reveal = function(path, opts)
    M.reveal(path, opts)
  end,
  refresh = function()
    M.refresh()
  end,
  close = function()
    M.close()
  end,
  register_decorator = function(fn)
    M.register_decorator(fn)
  end,
  -- The current tree root path, or nil when the tree isn't built (git uses this).
  root = function()
    return tree and tree.root.path
  end,
  -- Introspection for custom actions: the tree state and the node under the cursor.
  state = function()
    return tree
  end,
  node = function()
    return tree and actions.current(tree)
  end,
}
M.api = api

-- ----- the auto-refresh watch ------------------------------------------------

-- Watch the root recursively and re-scan on change. Best-effort — a build with no
-- native watcher (browser/serverless) rejects the first pull, surfaced once via run's
-- catch, degrading to manual refresh. Stops any prior watch first (root changes).
local function start_watch()
  if not tree or not tree.config.watch then
    return
  end
  if tree._watch then
    pcall(function()
      tree._watch:stop()
    end)
    tree._watch = nil
  end
  run(function()
    local w = nx.fs.watch(tree.root.path, { recursive = true })
    tree._watch = w
    for _ in nx.await_each(w) do
      model.refresh(tree, tree.root)
      render({ restore_cursor = false })
    end
  end)
end

-- Run `fn` once the view's backing buffer exists (its bufnr arrives a tick after the
-- create/mount ops drain). `nx.wait_for` polls between ticks until then.
local function when_buf(fn)
  nx.wait_for(function()
    return tree and tree.view:bufnr()
  end)
    :next(fn)
    :catch(function() end)
end

-- ----- build / lifecycle -----------------------------------------------------

-- Build the tree on first open: mint the view, mount it in the configured dock side,
-- load + render the root, install the bindings + on_attach + git, arm the watch, then
-- land focus back in the editor.
local function build()
  if not hl_applied then
    highlights.apply(M.config.highlights)
    hl_applied = true
  end

  tree = {
    root = model.root(M.config.root or vim.fn.getcwd()),
    ns = nx.ns.create("nxvim-tree"),
    flat = {},
    filter = nil,
    config = M.config,
    view = nx.view.create({ name = "nxvim-tree", filetype = "nxtree" }),
    _clipboard = nil,
    _watch = nil,
  }
  tree.view:on_select(function()
    run(function()
      actions.select(tree, api)
    end)
  end)
  tree.view:mount({ dock = M.config.position, size = M.config.width })

  run(function()
    model.expand(tree, tree.root)
    render({ restore_cursor = false })
  end)

  when_buf(function()
    local buf = tree.view:bufnr()
    keymap.install(tree, api)
    if M.config.git then
      require("nxvim-tree.git").enable(api)
    end
    if type(M.config.on_attach) == "function" then
      M.config.on_attach(api, buf)
    end
    start_watch()
    tree._maps_installed = true -- a readiness signal (the action maps are live)
  end)

  nx.layer.main()
end

-- toggle() — build + mount on first use, then toggle the dock's visibility.
function M.toggle()
  if tree == nil then
    build()
  else
    nx.dock.toggle(M.config.position)
  end
end

-- open() — open + focus the sidebar (build if needed).
function M.open()
  if tree == nil then
    build()
  else
    nx.dock.show(M.config.position)
    tree.view:focus()
  end
end

-- close() — hide the sidebar and return focus to the editor.
function M.close()
  if tree then
    nx.dock.hide(M.config.position)
    nx.layer.main()
  end
end

-- focus() — move focus into the tree (building it if needed).
function M.focus()
  M.open()
end

-- refresh() — re-scan the whole tree (preserving expansion) and re-render.
function M.refresh()
  if tree then
    run(function()
      model.refresh(tree, tree.root)
      render({ restore_cursor = true })
    end)
  end
end

-- set_root(path) — rebuild the model rooted at `path`, keeping the same view, and
-- re-arm the watch on the new root. Clears the filter and any pending clipboard.
function M.set_root(path)
  if not tree then
    return
  end
  tree.root = model.root(path)
  tree.filter = nil
  tree._clipboard = nil
  run(function()
    model.expand(tree, tree.root)
    render({ restore_cursor = false })
  end)
  start_watch()
  nx.notify("nxvim-tree: root → " .. tree.root.path)
end

-- destroy() — tear the tree down completely (stop the watch, drop the view buffer,
-- forget the singleton). The next open() rebuilds from scratch. Primarily for tests
-- and for a hard reset.
function M.destroy()
  if tree then
    if tree._watch then
      pcall(function()
        tree._watch:stop()
      end)
    end
    pcall(function()
      tree.view:close()
    end)
    tree = nil
  end
end

-- reveal(path, opts) — open the tree (building it if needed), expand the directories
-- along `path` (default: the file in the current window), land the cursor on its
-- node, and (by default) focus the sidebar. `opts.focus = false` moves the cursor but
-- bounces focus back to the editor (used by `follow`). A no-op for a path outside the
-- root.
function M.reveal(path, opts)
  opts = opts or {}
  local focus = opts.focus ~= false
  if tree == nil then
    build()
  end
  run(function()
    local target = path
    if not target or target == "" then
      target = vim.fn.expand("%:p")
    end
    if not target or target == "" then
      if focus then
        nx.notify("nxvim-tree: no file to reveal", 3)
      end
      return
    end

    local base = tree.root.path
    if base:sub(-1) ~= "/" then
      base = base .. "/"
    end
    if target:sub(1, #base) ~= base then
      if focus then
        nx.notify("nxvim-tree: " .. target .. " is outside the tree root", 3)
      end
      return
    end

    local segments = {}
    for seg in target:sub(#base + 1):gmatch("[^/]+") do
      segments[#segments + 1] = seg
    end
    if #segments == 0 then
      return
    end

    tree.filter = nil
    if not tree.root.loaded then
      model.load(tree, tree.root)
    end
    tree.root.expanded = true
    local node = tree.root
    for i, seg in ipairs(segments) do
      local child = model.find_child(node, seg)
      if not child then
        node = nil
        break
      end
      if i < #segments and child.type == "directory" then
        model.expand(tree, child)
      end
      node = child
    end

    render({ restore_cursor = false })
    if not node then
      if focus then
        nx.notify("nxvim-tree: " .. target .. " not found under the root", 3)
      end
      return
    end
    for i, n in ipairs(tree.flat) do
      if n == node then
        tree.view:set_cursor(i) -- this focuses the view…
        if not focus then
          nx.layer.main() -- …so bounce focus back when following.
        end
        return
      end
    end
  end)
end

-- bufnr() — the view's backing buffer number (or nil before the tree is built /
-- mounted). An introspection handle for add-ons and tests.
function M.bufnr()
  return tree and tree.view:bufnr()
end

-- _ready() — true once the tree is built AND its buffer-local action maps are
-- installed. The buffer exists (and the <CR> map works) a tick before the action
-- maps do; tests wait on this before feeding action keys (a / H / d / …).
function M._ready()
  return tree ~= nil and tree._maps_installed == true
end

-- ----- extensibility registries ----------------------------------------------

-- register_decorator(fn) — `fn(node) -> { sign_text=, sign_hl=, hl=, virt_text= }` (or
-- nil), merged into every visible line's decoration each render.
function M.register_decorator(fn)
  M.config._decorators[#M.config._decorators + 1] = fn
  render({ restore_cursor = false })
end

-- register_icons(map) — extend the extension/name → glyph table (see icons.lua).
function M.register_icons(map)
  icons.register(map)
  render({ restore_cursor = false })
end

-- register_action(key, fn) — bind a buffer-local `key` to `fn(tree, api)`, run inside
-- the async error-surfacing wrapper. Persists into the live mappings so a later
-- rebuild keeps it.
function M.register_action(key, fn)
  M.config.mappings[key] = fn
  if tree and tree.view:bufnr() then
    nx.keymap.set("n", key, function()
      run(function()
        fn(tree, api)
      end)
    end, { buffer = tree.view:bufnr(), desc = "nxvim-tree: custom" })
  end
end

-- ----- autocmds (wired once) -------------------------------------------------

-- BufEnter housekeeping while the tree is open: keep the NvimTreeOpenedFile highlight
-- fresh as you switch buffers, and — when `follow` is on — reveal the active file.
-- Wired once; the handler reads the live config so toggling `follow` needs no
-- re-register. Ignores the tree's own buffer (set_cursor focuses it → BufEnter) to
-- avoid a feedback loop.
local function wire_autocmds()
  if autocmds_wired then
    return
  end
  autocmds_wired = true
  nx.on("BufEnter", {}, function()
    if not tree or not tree.view:winid() then
      return
    end
    local cur = nx.win.buf(nx.win.current())
    if cur == tree.view:bufnr() then
      return
    end
    if tree.config.follow then
      local name = vim.fn.expand("%:p")
      if name and name ~= "" then
        M.reveal(name, { focus = false }) -- reveal renders, refreshing the opened-file tint
        return
      end
    end
    render({ restore_cursor = false }) -- refresh the opened-file highlight
  end)
end

-- ----- setup -----------------------------------------------------------------

-- setup(opts) — merge config, apply highlights + icon overrides, register the commands
-- and the toggle keymap. Re-runnable: a second call re-merges from defaults (so it is
-- a full reconfigure, not a partial patch) and re-applies, but keeps the singleton if
-- already built. See config.lua for the full option list and the mappable actions.
function M.setup(opts)
  M.config = config.merge(config.defaults(), opts)
  M.config._decorators = {}
  hl_applied = false
  highlights.apply(M.config.highlights)
  hl_applied = true
  if next(M.config.icon_overrides) then
    icons.register(M.config.icon_overrides)
  end

  -- A live tree adopts the new config (so :NxvimTree, dock side, mappings stay sane).
  if tree then
    tree.config = M.config
  end

  nx.command("NxvimTree", function()
    M.toggle()
  end, { desc = "Toggle the nxvim-tree file explorer" })
  nx.command("NxvimTreeOpen", function()
    M.open()
  end, { desc = "Open + focus the nxvim-tree file explorer" })
  nx.command("NxvimTreeClose", function()
    M.close()
  end, { desc = "Close the nxvim-tree file explorer" })
  nx.command("NxvimTreeRefresh", function()
    M.refresh()
  end, { desc = "Re-scan the nxvim-tree file explorer" })
  nx.command("NxvimTreeReveal", function()
    M.reveal()
  end, { desc = "Reveal the current file in nxvim-tree" })

  local key = M.config.toggle_key
  if key then
    nx.keymap.set("n", key, function()
      M.toggle()
    end, { desc = "Toggle nxvim-tree" })
  end

  wire_autocmds()

  if M.config.open_on_start then
    M.open()
  end

  return M
end

return M
