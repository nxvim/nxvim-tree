-- nxvim-tree.git — the built-in, opt-in git-status decorator (enable with `git = true`).
--
-- Zero coupling with the tree's core: it only uses the decorator seam
-- (`api.register_decorator`) and `api.refresh()`. It shells out to `git status
-- --porcelain` via `nx.run` (promise), builds a path → status map, and a decorator
-- turns that into a gutter sign per changed file plus a "dirty dot" on directories
-- that contain a change. It re-fetches on `BufWritePost`. With `git = false` (the
-- default) none of this runs, and a non-git directory simply leaves the tree
-- unmarked.
--
-- `classify(code)` is pure (a 2-char porcelain status → { sign, hl }) and exported so
-- the test suite can assert the mapping without a repo.

local M = {}

local function join(dir, name)
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

-- classify(code) — a porcelain XY status into { sign, hl }. "??" is untracked; a D in
-- either column is a deletion; an A is an addition; staged-only (X set, Y clear) tints
-- as staged; everything else is a modification.
function M.classify(code)
  if code == "??" then
    return { sign = "+", hl = "NvimTreeGitNew" }
  end
  local x, y = code:sub(1, 1), code:sub(2, 2)
  if x == "D" or y == "D" then
    return { sign = "-", hl = "NvimTreeGitDeleted" }
  elseif x == "A" or y == "A" then
    return { sign = "+", hl = "NvimTreeGitNew" }
  elseif y == " " and x ~= " " then
    return { sign = "✓", hl = "NvimTreeGitStaged" }
  end
  return { sign = "~", hl = "NvimTreeGitDirty" }
end

-- enable(api) — wire the decorator and the refetch autocmd. Idempotent per tree: the
-- caller (init.build) calls it once when `cfg.git` is on. `api` provides
-- register_decorator(fn), refresh(), and root() (the current tree root path).
function M.enable(api)
  local file_status = {} -- abspath -> { sign, hl }
  local dir_dirty = {} -- abspath -> true (an ancestor of a change)

  api.register_decorator(function(node)
    if node.type == "directory" then
      if dir_dirty[node.path] then
        return { sign_text = "•", sign_hl = "NvimTreeGitDirty" }
      end
    else
      local s = file_status[node.path]
      if s then
        return { sign_text = s.sign, sign_hl = s.hl }
      end
    end
  end)

  local function fetch()
    local root = api.root()
    nx.async(function()
      local res = nx.await(nx.run({ cmd = "git", args = { "status", "--porcelain" }, cwd = root }))
      if res.code ~= 0 then
        return -- not a git repo (or git missing): leave the tree unmarked
      end
      file_status, dir_dirty = {}, {}
      for line in (res.stdout .. "\n"):gmatch("([^\n]*)\n") do
        if #line > 3 then
          local code = line:sub(1, 2)
          local rel = line:sub(4)
          local arrow = rel:find(" %-> ") -- a rename is "old -> new"; mark the new path
          if arrow then
            rel = rel:sub(arrow + 4)
          end
          local abs = join(root, rel)
          file_status[abs] = M.classify(code)
          local p = abs:match("(.*)/[^/]+$") -- propagate the dirty flag to ancestors
          while p and #p >= #root do
            dir_dirty[p] = true
            p = p:match("(.*)/[^/]+$")
          end
        end
      end
      api.refresh()
    end)():catch(function(e)
      nx.notify("nxvim-tree.git: " .. tostring(type(e) == "table" and e.message or e), 4)
    end)
  end

  nx.on("BufWritePost", {}, fetch)
  fetch() -- initial paint
end

return M
