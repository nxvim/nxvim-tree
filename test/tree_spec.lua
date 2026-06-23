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

  -- The header and opened files are normalized relative to the cwd: with the cwd set to
  -- the root, the header is the cwd's basename (not the absolute path) and an opened file
  -- carries a cwd-relative buffer name. Restores the cwd so later tests are unaffected.
  nx.test.it("shows the root and opens files relative to the cwd", function(t)
    local prev = vim.fn.getcwd()
    vim.cmd("cd " .. ROOT)
    -- `:cd` drains at end-of-tick; wait until getcwd mirrors the new dir before reading it.
    local cwd = t:wait_for(function()
      local c = vim.fn.getcwd()
      return c == ROOT and c
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
end)
