-- nxvim-tree.actions — the user-facing operations (open / navigate / file ops).
--
-- Each action is `fn(tree, api)`:
--   tree   the singleton tree state (root, view, flat, config, clipboard, …)
--   api    the helper bundle init.lua hands every action:
--            api.render(opts)   re-render the tree (opts.restore_cursor keeps place)
--            api.run(body)      run an async body with error surfacing (rarely needed
--                               here — the keymap layer already wraps every action)
--            api.set_root(path) rebuild the model rooted at `path` and re-render
--            api.reveal(path)   reveal a path in the tree
--
-- Actions that touch `nx.fs` await it, so they run inside the async wrapper the
-- keymap layer (and the <CR> dispatch) provide. After a mutation an action re-loads
-- the affected directory and re-renders with the cursor preserved.
--
-- This module is the dispatch target named by `config.ACTIONS`; the names here match
-- those keys exactly, so `actions[name]` resolves a built-in for the keymap layer.

local model = require("nxvim-tree.model")

local M = {}

-- The node under the cursor, or nil if the view has no cursor line yet.
local function current(tree)
  local line = tree.view:line()
  return line and tree.flat[line]
end
M.current = current

-- The directory a "create"/"paste" should target: the node itself if a directory,
-- else its parent (so acting on a file targets its containing directory).
local function dir_of(node)
  return node.type == "directory" and node or node.parent
end

-- Reload `dir` from disk, ensure it is open, then re-render (keeping the cursor).
local function reload(tree, api, dir)
  dir.expanded = true
  model.load(tree, dir)
  api.render({ restore_cursor = true })
end

-- Move the view cursor onto `node` if it is currently visible. Returns true on a hit.
local function goto_node(tree, api, node)
  api.render({ restore_cursor = false })
  for i, n in ipairs(tree.flat) do
    if n == node then
      tree.view:set_cursor(i)
      return true
    end
  end
  return false
end

-- ----- opening ---------------------------------------------------------------

-- Yield until the next event-loop tick. A layer cross (nx.layer.main) is queued and
-- only applied at end-of-tick — *after* the editor drains queued ex-commands — so a
-- split issued in the same tick would target whatever layer is still focused. Awaiting
-- this lets the focus land first. (See open_file.)
local function next_tick()
  return nx.promise.new(function(resolve)
    nx.on_next_tick(resolve)
  end)
end

-- The path to hand nx.open: cwd-relative when the file is under the cwd (`:.`), else
-- absolute. The editor stores a buffer's name exactly as opened (it only absolutizes
-- for dedup), so opening relative keeps the buffer name — and everything that displays
-- it — relative to where the editor was launched.
local function open_target(path)
  return vim.fn.fnamemodify(path, ":.")
end

-- Open a file node in the main editor. `mode` is "edit" | "split" | "vsplit" | "tab".
-- Splits/tabs cross to the main layer first (so the new window is carved out of the
-- editor, not the sidebar dock), then open the file in it.
--
-- The cross MUST settle before the split: `nx.layer.main()` and `vim.cmd("split")`
-- both queue, and the editor runs queued ex-commands *before* the queued layer cross —
-- so issuing the split in the same tick splits the still-focused tree dock. Awaiting a
-- tick after the cross makes main the focused layer first; the split (and the open that
-- follows in the same later tick) then land in the editor.
local function open_file(node, mode)
  if mode == "edit" or mode == nil then
    nx.open(open_target(node.path), { where = "main" })
    return
  end
  nx.layer.main()
  nx.await(next_tick())
  if mode == "split" then
    vim.cmd("split")
  elseif mode == "vsplit" then
    vim.cmd("vsplit")
  elseif mode == "tab" then
    vim.cmd("tabnew")
  end
  nx.open(open_target(node.path))
end

-- select — the <CR>/`o` action: a directory toggles expand (lazy-loading on first
-- open); a file opens in the main editor.
function M.select(tree, api)
  local node = current(tree)
  if not node then
    return
  end
  if node.type == "directory" then
    if node.expanded then
      node.expanded = false
      api.render({ restore_cursor = true })
    else
      model.expand(tree, node)
      api.render({ restore_cursor = true })
    end
  else
    open_file(node, "edit")
  end
end

function M.open_split(tree)
  local node = current(tree)
  if node and node.type ~= "directory" then
    open_file(node, "split")
  end
end

function M.open_vsplit(tree)
  local node = current(tree)
  if node and node.type ~= "directory" then
    open_file(node, "vsplit")
  end
end

function M.open_tab(tree)
  local node = current(tree)
  if node and node.type ~= "directory" then
    open_file(node, "tab")
  end
end

-- ----- navigation ------------------------------------------------------------

function M.expand(tree, api)
  local node = current(tree)
  if node and node.type == "directory" and not node.expanded then
    model.expand(tree, node)
    api.render({ restore_cursor = true })
  end
end

-- collapse — an open directory closes; otherwise the cursor jumps to the parent (the
-- familiar `h` behaviour from nvim-tree / netrw).
function M.collapse(tree, api)
  local node = current(tree)
  if not node then
    return
  end
  if node.type == "directory" and node.expanded then
    node.expanded = false
    api.render({ restore_cursor = true })
  elseif node.parent then
    goto_node(tree, api, node.parent)
  end
end

function M.parent(tree, api)
  local node = current(tree)
  if node and node.parent then
    goto_node(tree, api, node.parent)
  end
end

function M.expand_all(tree, api)
  model.expand_all(tree, tree.root)
  api.render({ restore_cursor = true })
end

function M.collapse_all(tree, api)
  model.collapse_all(tree.root)
  api.render({ restore_cursor = true })
end

-- ----- root changes ----------------------------------------------------------

-- change_root — make the directory under the cursor the new tree root.
function M.change_root(tree, api)
  local node = current(tree)
  if node and node.type == "directory" then
    api.set_root(node.path)
  end
end

-- up_root — make the parent of the current root the new root (a no-op at "/").
function M.up_root(tree, api)
  local parent = tree.root.path:match("^(.*)/[^/]+$")
  if parent == "" then
    parent = "/"
  end
  if parent and parent ~= tree.root.path then
    api.set_root(parent)
  end
end

-- ----- file operations -------------------------------------------------------

function M.create(tree, api)
  local node = current(tree)
  if not node then
    return
  end
  local dir = dir_of(node)
  local name = nx.await(nx.ui.input({ prompt = "Create (end with / for a directory): " }))
  if not name or name == "" then
    return
  end
  local is_dir = name:sub(-1) == "/"
  local target = model.join(dir.path, (name:gsub("/+$", "")))
  if nx.await(nx.fs.exists(target)) then
    return nx.notify("nxvim-tree: " .. target .. " already exists", 3)
  end
  if is_dir then
    nx.await(nx.fs.mkdir(target, { recursive = true }))
  else
    -- Create any missing parent directories (so "a/b/c.txt" works), then the file.
    local parent = target:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and not nx.await(nx.fs.exists(parent)) then
      nx.await(nx.fs.mkdir(parent, { recursive = true }))
    end
    nx.await(nx.fs.write(target, ""))
  end
  reload(tree, api, dir)
end

function M.rename(tree, api)
  local node = current(tree)
  if not node or node.depth == 0 then
    return
  end
  local new = nx.await(nx.ui.input({ prompt = "Rename: ", default = node.name }))
  if not new or new == "" or new == node.name then
    return
  end
  nx.await(nx.fs.rename(node.path, model.join(node.parent.path, new)))
  reload(tree, api, node.parent)
end

function M.delete(tree, api)
  local node = current(tree)
  if not node or node.depth == 0 then
    return
  end
  local ok = nx.await(nx.ui.confirm("Delete " .. node.name .. "?", { default = false }))
  if not ok then
    return
  end
  nx.await(nx.fs.remove(node.path, { recursive = node.type == "directory" }))
  reload(tree, api, node.parent)
end

-- cut/copy mark a source; paste consumes it. The marked node is tinted in the render
-- (NvimTreeCutHL / NvimTreeCopiedHL) so the pending operation is visible.
local function mark(tree, api, op)
  local node = current(tree)
  if not node or node.depth == 0 then
    return
  end
  tree._clipboard = { node = node, op = op }
  api.render({ restore_cursor = true })
  nx.notify(("nxvim-tree: %s %s (press p to paste)"):format(op, node.name))
end

function M.cut(tree, api)
  mark(tree, api, "cut")
end

function M.copy(tree, api)
  mark(tree, api, "copy")
end

function M.clear_clipboard(tree, api)
  if tree._clipboard then
    tree._clipboard = nil
    api.render({ restore_cursor = true })
  end
end

function M.paste(tree, api)
  local clip = tree._clipboard
  if not clip then
    return nx.notify("nxvim-tree: nothing to paste (cut with x or copy with c first)", 3)
  end
  local node = current(tree)
  if not node then
    return
  end
  local src = clip.node
  local dir = dir_of(node)
  local dest = model.join(dir.path, src.name)
  if dest == src.path then
    return nx.notify("nxvim-tree: source and destination are the same", 3)
  end
  if nx.await(nx.fs.exists(dest)) then
    return nx.notify("nxvim-tree: " .. dest .. " already exists", 3)
  end

  if clip.op == "copy" then
    nx.await(nx.fs.copy(src.path, dest, { recursive = src.type == "directory" }))
  else
    nx.await(nx.fs.rename(src.path, dest))
  end

  local old_parent = src.parent
  tree._clipboard = nil
  -- A move empties the old parent; reload it too (if loaded and distinct).
  if clip.op == "cut" and old_parent and old_parent ~= dir and old_parent.loaded then
    model.load(tree, old_parent)
  end
  reload(tree, api, dir)
end

function M.yank_path(tree)
  local node = current(tree)
  if not node then
    return
  end
  nx.reg.set('"', node.path)
  nx.reg.set("+", node.path)
  nx.notify("nxvim-tree: yanked " .. node.path)
end

-- ----- view-level actions ----------------------------------------------------

function M.refresh(tree, api)
  model.refresh(tree, tree.root)
  api.render({ restore_cursor = true })
end

function M.toggle_hidden(tree, api)
  tree.config.hidden = not tree.config.hidden
  model.refresh(tree, tree.root)
  api.render({ restore_cursor = true })
  nx.notify("nxvim-tree: hidden files " .. (tree.config.hidden and "shown" or "hidden"))
end

function M.reveal(tree, api)
  api.reveal()
end

function M.filter(tree, api)
  local q = nx.await(nx.ui.input({ prompt = "Filter: ", default = tree.filter or "" }))
  if q == nil then
    return -- cancelled: keep the current filter
  end
  tree.filter = (q ~= "") and q or nil
  api.render({ restore_cursor = true })
end

function M.clear_filter(tree, api)
  if tree.filter then
    tree.filter = nil
    api.render({ restore_cursor = true })
  end
end

function M.close(tree, api)
  api.close()
end

return M
