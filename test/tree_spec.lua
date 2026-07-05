-- End-to-end tree behaviour: open the explorer over a temp directory and drive it
-- with real keys, asserting on the rendered view buffer. Run with
-- `nxvim --test-plugin`.
--
-- The view's <CR> activation map is installed synchronously at view-create, so
-- expand/collapse via <CR> is reliable immediately; the *action* maps (a / H / d / …)
-- arrive a tick later, so tests wait on `tree._ready()` before feeding those. The
-- input/confirm prompts both run in command-line mode, so we wait for mode "c" before
-- answering them.

local tree = require("nxvim-tree")
local model = require("nxvim-tree.model")
local fs = nx.fs

local ROOT

-- The joined text of the tree view buffer right now (or "" before it exists).
local function buf_text()
  local b = tree.bufnr()
  if not b then
    return ""
  end
  return table.concat(nx.buf.lines(b, 0, -1, false), "\n")
end

-- Wait until the view text contains `needle`, returning the text.
local function wait_contains(t, needle)
  return t:wait_for(function()
    local txt = buf_text()
    return txt:find(needle, 1, true) and txt
  end)
end

-- How many open windows show a buffer whose basename is `name`.
local function count_showing(name)
  local n = 0
  for _, w in ipairs(nx.win.list()) do
    if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(nx.win.buf(w)), ":t") == name then
      n = n + 1
    end
  end
  return n
end

-- The basename of the focused window's buffer.
local function current_name()
  return vim.fn.fnamemodify(vim.fn.expand("%:p"), ":t")
end

-- Open the tree, wait until it has rendered and its action maps are live, and focus
-- it so buffer-local keys fire.
local function open_ready(t)
  tree.open()
  wait_contains(t, "readme.txt")
  t:wait_for(function()
    return tree._ready()
  end)
  tree.focus()
  t:feed("") -- settle a tick so focus lands before we read/feed action keys
end

nx.test.describe("nxvim-tree", function()
  nx.test.before_each(function()
    tree.destroy()
    ROOT = nx.test.tempdir()
    nx.await(fs.write(model.join(ROOT, "readme.txt"), "hi"))
    nx.await(fs.mkdir(model.join(ROOT, "src")))
    nx.await(fs.write(model.join(ROOT, "src/main.rs"), ""))
    nx.await(fs.write(model.join(ROOT, ".secret"), ""))
    tree.setup({ root = ROOT, watch = false, toggle_key = false })
  end)

  nx.test.after_each(function()
    tree.destroy()
  end)

  nx.test.it("renders the root's entries, directories suffixed and dotfiles hidden", function(t)
    tree.open()
    local txt = wait_contains(t, "readme.txt")
    nx.test.expect(txt).to_contain("src/")
    nx.test.expect(txt).never.to_contain(".secret")
  end)

  nx.test.it("expands a directory on <CR>", function(t)
    open_ready(t)
    t:feed("j") -- onto src/ (line 2)
    t:feed("<CR>") -- expand
    nx.test.expect(wait_contains(t, "main.rs")).to_contain("main.rs")
  end)

  nx.test.it("collapses an expanded directory on <CR>", function(t)
    open_ready(t)
    t:feed("j"):feed("<CR>")
    wait_contains(t, "main.rs")
    t:feed("<CR>") -- cursor was kept on src/ → this collapses it
    local gone = t:wait_for(function()
      return not buf_text():find("main.rs", 1, true)
    end)
    nx.test.expect(gone).to_be_truthy()
  end)

  nx.test.it("toggles hidden files with H", function(t)
    open_ready(t)
    t:feed("H")
    nx.test.expect(wait_contains(t, ".secret")).to_contain(".secret")
  end)

  nx.test.it("filters by name with / and clears with <Esc>", function(t)
    open_ready(t)
    t:feed("/")
    t:wait_for(function()
      return t:mode() == "c"
    end)
    t:feed("readme<CR>")
    local filtered = t:wait_for(function()
      local txt = buf_text()
      return txt:find("readme.txt", 1, true) and not txt:find("src/", 1, true) and txt
    end)
    nx.test.expect(filtered).to_contain("readme.txt")
    nx.test.expect(filtered).never.to_contain("src/")
    -- Clear the filter; src/ comes back.
    t:feed("<Esc>")
    nx.test.expect(wait_contains(t, "src/")).to_contain("src/")
  end)

  nx.test.it("creates a file with `a`", function(t)
    open_ready(t) -- cursor on the root → creates in the root directory
    t:feed("a")
    t:wait_for(function()
      return t:mode() == "c"
    end)
    t:feed("brand_new.txt<CR>")
    nx.test.expect(wait_contains(t, "brand_new.txt")).to_contain("brand_new.txt")
    nx.test.expect(nx.await(fs.exists(model.join(ROOT, "brand_new.txt")))).to_be_truthy()
  end)

  nx.test.it("deletes a file with `d` after confirming", function(t)
    open_ready(t)
    t:feed("j"):feed("j") -- root(1) → src/(2) → readme.txt(3)
    t:feed("d")
    t:wait_for(function()
      return t:mode() == "c"
    end)
    t:feed("y") -- confirm
    local gone = t:wait_for(function()
      return not buf_text():find("readme.txt", 1, true)
    end)
    nx.test.expect(gone).to_be_truthy()
    nx.test.expect(nx.await(fs.exists(model.join(ROOT, "readme.txt")))).to_be_falsy()
  end)

  nx.test.it("opens a file in the main editor on <CR>", function(t)
    open_ready(t)
    t:feed("j"):feed("<CR>") -- expand src/
    wait_contains(t, "main.rs")
    -- move onto main.rs (root=1, src=2, main.rs=3) and open it
    t:feed("j"):feed("<CR>")
    local opened = t:wait_for(function()
      local name = vim.fn.expand("%:p")
      return name:find("main.rs", 1, true) and name
    end)
    nx.test.expect(opened).to_contain("main.rs")
  end)

  -- A split/tab open must carve the new window out of the MAIN editor, not the tree
  -- dock. The cross to main is queued and only lands after the queued split command
  -- runs, so opening the split in the same tick would split the dock; the action yields
  -- a tick so the focus lands first. A dock split would duplicate the tree buffer into a
  -- second window — so "exactly one window shows the tree buffer" is the regression check.
  nx.test.it("opens a split in the main editor with `s`, never splitting the dock", function(t)
    open_ready(t)
    t:feed("j"):feed("<CR>") -- expand src/
    wait_contains(t, "main.rs")
    t:feed("j") -- onto main.rs
    t:feed("s") -- open in a horizontal split
    local opened = t:wait_for(function()
      local name = vim.fn.expand("%:p")
      return name:find("main.rs", 1, true) and name
    end)
    nx.test.expect(opened).to_contain("main.rs")

    local treebuf = tree.bufnr()
    local showing = 0
    for _, w in ipairs(nx.win.list()) do
      if nx.win.buf(w) == treebuf then
        showing = showing + 1
      end
    end
    nx.test.expect(showing).to_be(1)
  end)

  -- Opening a file that is already shown in a main-editor window must JUMP to that
  -- window ('switchbuf'), not reload a duplicate into the focused one. The action
  -- passes `nx.open(..., { reuse = true })`; the regression is a second window
  -- ending up on the same file (and the other file getting clobbered).
  nx.test.it("jumps to an already-open window instead of duplicating it on <CR>", function(t)
    open_ready(t)
    local main_rs = model.join(ROOT, "src/main.rs")
    local readme = model.join(ROOT, "readme.txt")

    -- Lay out two main-editor windows: A shows main.rs, B (focused) shows readme.txt.
    nx.open(main_rs, { where = "main" }) -- cross to the editor
    t:wait_for(function()
      return current_name() == "main.rs" and true
    end)
    t:feed(":only<CR>") -- collapse to a single main window (window A = main.rs)
    t:feed(":vsplit<CR>") -- window B, still on main.rs…
    t:feed(":edit " .. readme .. "<CR>") -- …now on readme.txt (the current window)
    t:wait_for(function()
      return current_name() == "readme.txt" and count_showing("main.rs") == 1 and true
    end)

    -- Reveal main.rs in the tree (focuses the sidebar, cursor on its node) and open it.
    -- reuse must FOCUS window A, leaving window B (readme.txt) untouched — never
    -- reloading main.rs into window B (which would clobber readme.txt).
    tree.reveal(main_rs)
    t:wait_for(function()
      return vim.api.nvim_get_current_buf() == tree.bufnr() and true
    end)
    t:feed("<CR>")
    local jumped = t:wait_for(function()
      return current_name() == "main.rs" and count_showing("readme.txt") == 1 and true
    end)
    nx.test.expect(jumped).to_be_truthy()
    nx.test.expect(count_showing("main.rs")).to_be(1) -- no duplicate window
    nx.test.expect(count_showing("readme.txt")).to_be(1) -- readme.txt not clobbered
  end)

  -- The header and opened files are normalized relative to the cwd: with the cwd set to
  -- the root, the header is the cwd's basename (not the absolute path) and an opened file
  -- carries a cwd-relative buffer name. Restores the cwd so later tests are unaffected.
  nx.test.it("shows the root and opens files relative to the cwd", function(t)
    local prev = vim.fn.getcwd()
    vim.cmd("cd " .. ROOT)
    -- `:cd` drains at end-of-tick; wait until getcwd mirrors the new dir before reading it.
    -- The editor canonicalizes the cwd, so on macOS the tempdir's `/var/folders` symlink
    -- resolves to `/private/var/...` and getcwd never equals ROOT verbatim — accept either
    -- the tempdir path or its realpath, and use whatever getcwd actually reports downstream.
    local root_real = nx.await(fs.realpath(ROOT))
    local cwd = t:wait_for(function()
      local c = vim.fn.getcwd()
      return (c == ROOT or c == root_real) and c
    end)
    tree.destroy()
    tree.setup({ root = cwd, watch = false, toggle_key = false })
    open_ready(t)

    local header = nx.buf.lines(tree.bufnr(), 0, 1, false)[1]
    nx.test.expect(header).to_contain(vim.fn.fnamemodify(cwd, ":t"))
    nx.test.expect(header).never.to_contain(cwd)

    t:feed("j"):feed("<CR>") -- expand src/
    wait_contains(t, "main.rs")
    t:feed("j"):feed("<CR>") -- open main.rs
    -- The opened buffer's stored name is cwd-relative, not the absolute path.
    local name = t:wait_for(function()
      local n = vim.fn.expand("%")
      return n ~= "" and n:find("main.rs", 1, true) and n
    end)
    nx.test.expect(name).to_be("src/main.rs")

    vim.cmd("cd " .. prev)
  end)

  -- The combination the bundled example uses (git + follow + open_on_start) must
  -- build cleanly — git.enable shells out, follow wires an autocmd, open_on_start
  -- opens during setup. A non-git tempdir leaves the tree unmarked but errorless.
  nx.test.it("builds with git + follow + open_on_start (the example config)", function(t)
    tree.destroy()
    tree.setup({
      root = ROOT,
      watch = false,
      toggle_key = false,
      git = true,
      follow = true,
      open_on_start = true,
    })
    nx.test.expect(wait_contains(t, "readme.txt")).to_contain("readme.txt")
  end)

  -- A re-render (watch fire, refresh, BufEnter) must repaint the decoration — the
  -- indent guides, icon/name highlights, and git signs — in the SAME tick it replaces
  -- the lines, never a tick later, or the tree flashes undecorated on every update.
  -- With the buffer already mounted the marks go on synchronously: wipe the namespace,
  -- re-render, and assert the marks are back without yielding a tick.
  nx.test.it("repaints decoration synchronously on re-render (no flicker)", function(t)
    open_ready(t)
    local state = tree.api.state()
    local buf = state.view:bufnr()
    -- The first render decorated the lines.
    t:wait_for(function()
      return #nx.buf.extmarks(buf, state.ns, 0, -1) > 0
    end)
    -- Wipe the decoration and re-render; the marks must reappear in this same chunk.
    nx.buf.clear_namespace(buf, state.ns, 0, -1)
    require("nxvim-tree.render").render(state, { restore_cursor = false })
    nx.test.expect(#nx.buf.extmarks(buf, state.ns, 0, -1)).never.to_be(0)
  end)

  -- The auto-refresh watch is per-EXPANDED-directory, not one recursive watch over the
  -- whole tree: only directories whose contents are visible are watched, so a large
  -- collapsed subtree costs nothing (and on macOS — where the backend is kqueue, one fd
  -- per watched path — a recursive whole-tree watch would exhaust file descriptors).
  -- Expanding a directory arms its watch; collapsing it drops the watch again.
  nx.test.it("watches only expanded directories, arming/dropping on expand/collapse", function(t)
    tree.destroy()
    tree.setup({ root = ROOT, watch = true, toggle_key = false })
    open_ready(t)

    local src = model.join(ROOT, "src")
    local function watched()
      local set = {}
      for _, p in ipairs(tree._watched_paths()) do
        set[p] = true
      end
      return set
    end

    -- Initially only the root is expanded → only the root is watched; src/ is collapsed.
    t:wait_for(function()
      local w = watched()
      return w[ROOT] and not w[src]
    end)

    -- Expand src/ → its watch arms.
    t:feed("j"):feed("<CR>")
    wait_contains(t, "main.rs")
    t:wait_for(function()
      return watched()[src]
    end)

    -- Collapse src/ → its watch drops; the root's stays.
    t:feed("<CR>")
    t:wait_for(function()
      local w = watched()
      return w[ROOT] and not w[src]
    end)
    nx.test.expect(watched()[src]).to_be_falsy()
  end)

  -- The per-directory watch isn't just placed — it fires: a file created on disk
  -- directly inside an expanded directory re-scans that one directory and shows up
  -- without any manual refresh. (Sleeps a beat first to let the native watcher actually
  -- arm before the write, mirroring the server's own fs-watch test.)
  nx.test.it("auto-refreshes an expanded directory on a disk change", function(t)
    tree.destroy()
    tree.setup({ root = ROOT, watch = true, toggle_key = false })
    open_ready(t)
    t:feed("j"):feed("<CR>") -- expand src/
    wait_contains(t, "main.rs")

    local src = model.join(ROOT, "src")
    t:wait_for(function() -- the src/ watch handle exists in Lua…
      for _, p in ipairs(tree._watched_paths()) do
        if p == src then
          return true
        end
      end
    end)
    t:sleep(200) -- …give the native backend a beat to actually arm before we change disk

    nx.await(fs.write(model.join(ROOT, "src/extra.rs"), ""))
    nx.test.expect(wait_contains(t, "extra.rs")).to_contain("extra.rs")
  end)

  -- Mouse support. The editor's native <LeftMouse> default places the view cursor on
  -- the clicked node *before* the mapped body runs (covered by the server's own
  -- mouse.rs), so the click actions read `current(tree)` like any keyboard action. We
  -- drive them the same way: move the cursor with a real motion, then invoke the body
  -- the config wires to the mouse key. A double click fires mouse_click then mouse_open.
  local actions = require("nxvim-tree.actions")

  nx.test.it("wires the default left-click mappings", function()
    local d = require("nxvim-tree.config").defaults()
    nx.test.expect(d.mappings["<LeftMouse>"]).to_be("mouse_click")
    nx.test.expect(d.mappings["<2-LeftMouse>"]).to_be("mouse_open")
  end)

  nx.test.it("single-clicks a directory to expand and collapse it (mouse_click)", function(t)
    open_ready(t)
    local state = tree.api.state()
    t:feed("j") -- cursor onto src/ (a real click lands here via the native default)
    actions.mouse_click(state, tree.api) -- single click expands the directory
    nx.test.expect(wait_contains(t, "main.rs")).to_contain("main.rs")
    actions.mouse_click(state, tree.api) -- a second single click collapses it
    local gone = t:wait_for(function()
      return not buf_text():find("main.rs", 1, true)
    end)
    nx.test.expect(gone).to_be_truthy()
  end)

  nx.test.it("single-click on a file does NOT open it (mouse_click)", function(t)
    open_ready(t)
    local state = tree.api.state()
    t:feed("j"):feed("j") -- root(1) → src/(2) → readme.txt(3)
    actions.mouse_click(state, tree.api) -- a single click on a file is a no-op
    t:feed("") -- settle a tick
    -- Focus never left the tree: the active buffer is not the file.
    nx.test.expect(vim.fn.expand("%:p"):find("readme.txt", 1, true)).to_be_nil()
  end)

  nx.test.it("double-clicks a file to open it in the main editor (mouse_open)", function(t)
    open_ready(t)
    local state = tree.api.state()
    t:feed("j") -- onto src/
    actions.mouse_click(state, tree.api) -- expand it (the double-click's first press)
    wait_contains(t, "main.rs")
    t:feed("j") -- onto main.rs (root1 src2 main.rs3)
    actions.mouse_open(state, tree.api) -- the second press opens the file
    local opened = t:wait_for(function()
      local name = vim.fn.expand("%:p")
      return name:find("main.rs", 1, true) and name
    end)
    nx.test.expect(opened).to_contain("main.rs")
  end)

  -- A double click on a DIRECTORY must toggle it exactly once: the first press
  -- (mouse_click) expands it, the second (mouse_open, file-only) ignores it. The two
  -- gestures never both act on one node, so the directory ends up expanded, not flicked
  -- open-then-shut.
  nx.test.it("double-click on a directory toggles it once (gestures don't overlap)", function(t)
    open_ready(t)
    local state = tree.api.state()
    t:feed("j") -- onto src/
    actions.mouse_click(state, tree.api) -- first press: expand
    actions.mouse_open(state, tree.api) -- second press: file-only → ignores the dir
    nx.test.expect(wait_contains(t, "main.rs")).to_contain("main.rs")
  end)

  -- Right-click context menu. A mapped <RightMouse> does NOT move the cursor, so
  -- mouse_menu resolves the clicked node from nx.getmousepos() and pops an nx.ui.select
  -- of operations for it. menu_for builds that list (context-dependent), and the chosen
  -- entry dispatches a built-in action — so we check both the composition and one full
  -- pop-and-run flow.

  -- Find the node for a name in the current flat list (the render's userdata order).
  local function node_named(name)
    for _, n in ipairs(tree.api.state().flat) do
      if n.name == name or n.name:match("[^/]+$") == name then
        return n
      end
    end
  end

  -- The set of labels menu_for offers for `node`.
  local function menu_labels(node)
    local labels = {}
    for _, it in ipairs(actions._menu_for(tree.api.state(), node)) do
      labels[it.label] = true
    end
    return labels
  end

  nx.test.it("wires <RightMouse> to the context menu", function()
    local d = require("nxvim-tree.config").defaults()
    nx.test.expect(d.mappings["<RightMouse>"]).to_be("mouse_menu")
  end)

  nx.test.it("offers file ops for a file and dir ops for a directory", function(t)
    open_ready(t)
    local file = menu_labels(node_named("readme.txt"))
    nx.test.expect(file["Open"]).to_be_truthy()
    nx.test.expect(file["Open in split"]).to_be_truthy()
    nx.test.expect(file["Rename…"]).to_be_truthy()
    nx.test.expect(file["Delete…"]).to_be_truthy()
    nx.test.expect(file["Expand"]).to_be_falsy() -- a file is not expandable

    local dir = menu_labels(node_named("src"))
    nx.test.expect(dir["Expand"]).to_be_truthy()
    nx.test.expect(dir["New file / directory…"]).to_be_truthy()
    nx.test.expect(dir["Set as root"]).to_be_truthy()
    nx.test.expect(dir["Open in split"]).to_be_falsy() -- you don't "open" a directory
  end)

  nx.test.it("omits rename/delete on the root and shows paste only with a clipboard", function(t)
    open_ready(t)
    local state = tree.api.state()
    local root = menu_labels(state.root)
    nx.test.expect(root["Rename…"]).to_be_falsy() -- the root has no parent to rename within
    nx.test.expect(root["Delete…"]).to_be_falsy()
    nx.test.expect(root["Paste"]).to_be_falsy() -- nothing on the clipboard yet

    state._clipboard = { node = node_named("readme.txt"), op = "copy" }
    nx.test.expect(menu_labels(state.root)["Paste"]).to_be_truthy()
  end)

  nx.test.it("every menu entry names a real action (no dangling dispatch)", function(t)
    open_ready(t)
    local state = tree.api.state()
    state._clipboard = { node = node_named("readme.txt"), op = "copy" } -- surface Paste too
    for _, node in ipairs({ state.root, node_named("src"), node_named("readme.txt") }) do
      for _, it in ipairs(actions._menu_for(state, node)) do
        nx.test.expect(type(actions[it.action])).to_be("function")
      end
    end
  end)

  -- The full gesture: right-click src/ → the menu pops → confirming its first entry
  -- ("Expand") expands the clicked directory. The cursor starts on the root, so the op
  -- landing on src/ proves the menu used the CLICKED cell (getmousepos), not the cursor.
  nx.test.it("pops the menu on right-click and runs the chosen op on the clicked node", function(t)
    open_ready(t)
    local state = tree.api.state()
    state.view:set_cursor(1) -- cursor on the root, not on src/
    -- Stand in for the server's mouse mirror: a right-click on src/ (flat line 2). The
    -- real signal is identical — getmousepos() reads exactly this mirror.
    nx._mouse_pos = { winid = state.view:winid(), line = 2 }
    tree.api.run(function()
      actions.mouse_menu(state, tree.api)
    end)
    t:feed("", { settle = 2 }) -- let the set_cursor + select-open ops drain
    t:feed("<CR>") -- confirm the first entry ("Expand")
    nx.test.expect(wait_contains(t, "main.rs")).to_contain("main.rs")
  end)

  nx.test.it("changes the root with `>` and ascends with `<`", function(t)
    open_ready(t)
    t:feed("j") -- onto src/
    t:feed(">") -- src becomes the root
    -- The header is now the src path and main.rs is a top-level entry.
    local txt = wait_contains(t, "main.rs")
    nx.test.expect(txt).to_contain(model.join(ROOT, "src"))
    nx.test.expect(txt).never.to_contain("readme.txt")
    -- Ascend back to the original root.
    t:feed("<")
    nx.test.expect(wait_contains(t, "readme.txt")).to_contain("readme.txt")
  end)

  -- Cross-session persistence: the plugin stashes a snapshot (root + expanded dirs +
  -- cursor) in its own shada slice on every structural change / cursor move, and rebuilds
  -- the sidebar from it on restore. This drives the CONTENT half of that path in-process
  -- (the window-adoption half is covered by the server session tests): expand a dir, read
  -- back the saved snapshot, then rebuild from it and assert the dir comes back open.
  nx.test.it("persists the expanded set + cursor and restores them across a rebuild", function(t)
    open_ready(t)
    t:feed("j") -- move the cursor onto src/
    t:feed("<CR>") -- expand src/
    wait_contains(t, "main.rs")

    -- The snapshot records the root, src/ among the expanded dirs, and the cursor's node.
    local snap = tree._session()
    nx.test.expect(type(snap)).to_be("table")
    nx.test.expect(snap.root).to_be(ROOT)
    nx.test.expect(snap.expanded).to_contain(model.join(ROOT, "src"))
    nx.test.expect(snap.cursor).to_be(model.join(ROOT, "src"))

    -- Rebuilding from that snapshot (the content half of on_restore) brings src/ back
    -- expanded — main.rs shows without a manual expand.
    tree._restore(snap)
    nx.test.expect(wait_contains(t, "main.rs")).to_contain("main.rs")
  end)

  -- A stale snapshot naming a directory since deleted on disk must not sink the whole
  -- restore: the missing dir is skipped, the rest of the tree still renders.
  nx.test.it("tolerates a stale snapshot whose expanded dir has vanished", function(t)
    open_ready(t)
    tree._restore({
      root = ROOT,
      expanded = { ROOT, model.join(ROOT, "does-not-exist"), model.join(ROOT, "src") },
      cursor = model.join(ROOT, "src"),
    })
    -- src/ still expands (main.rs shows); the bogus path was silently skipped.
    nx.test.expect(wait_contains(t, "main.rs")).to_contain("main.rs")
  end)

  -- Sidebar chrome (like nvim-tree): the tree window remaps Normal→NvimTreeNormal
  -- (its own darker background) and turns on `cursorline` to highlight the row. The
  -- background remap rides the dock (so it survives parking/restore); cursorline is
  -- a window option on the tree window itself.
  nx.test.it("gives the sidebar a dark background (winhighlight) and cursorline", function(t)
    open_ready(t)
    local view = tree.api.state().view
    local win = t:wait_for(function()
      return view:winid()
    end)
    -- The window option is applied a tick after mount (winid settles cross-tick).
    t:wait_for(function()
      return nx.wo[win].cursorline == true
    end)
    nx.test.expect(nx.wo[win].cursorline).to_be_truthy()
    -- The dock carries the Normal→NvimTreeNormal remap (read back from its opt cache;
    -- the default tree position is "left").
    local whl = nx.dock.opt("left").winhighlight or ""
    nx.test.expect(whl:find("Normal:NvimTreeNormal", 1, true)).to_be_truthy()
    nx.test.expect(whl:find("EndOfBuffer:NvimTreeEndOfBuffer", 1, true)).to_be_truthy()
  end)
end)
