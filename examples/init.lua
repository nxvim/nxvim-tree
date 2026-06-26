-- ~~~ Runnable demo for nxvim-tree ~~~
--
-- Run it from the repo root:
--
--     NXVIM_CONFIG=examples nxvim examples/sample/readme.txt
--
-- TRY IT interactively (the sidebar opens on start):
--   <leader>e / :NxvimTree   toggle the sidebar (left dock)
--   j / k                    move; <CR> / o on a dir toggles, on a file OPENS it in
--                            the MAIN editor (not inside the sidebar)
--   l / h                    expand / collapse (h on a leaf jumps to the parent)
--   single-click a dir       expand / collapse it; double-click a file OPENS it;
--                            the wheel scrolls the sidebar
--   s / v / t                open the file in a split / vsplit / new tab
--   E / W                    expand-all / collapse-all
--   a                        create (end the name with "/" for a directory)
--   r  rename   d  delete (confirms)
--   x  cut      c  copy      p  paste (move/copy under the cursor's dir)
--   y                        yank the absolute path to the " and + registers
--   / filter (Esc clears)    R  refresh        H  toggle hidden files
--   > / <                    descend into / ascend out of the root directory
--   f                        reveal the file open in the main window
--   q                        close the sidebar
--
-- The leader is space here; set it before anything maps <leader>.
vim.g.mapleader = " "

-- Load the plugin straight from this repo (a local-dev spec: `dir` is never cloned).
-- A real config would instead use `{ "davidrios/nxvim-tree", config = ... }` and
-- `:PluginSync`.
nx.plugins({
  {
    name = "nxvim-tree",
    dir = vim.fn.expand("<sfile>:p:h:h"), -- the repo root (this file's grandparent dir)
    config = function()
      require("nxvim-tree").setup({
        width = 34,
        git = true, -- colour entries by git status (this repo is one)
        follow = true, -- keep the tree cursor on the file you're editing
        open_on_start = true, -- show the tree immediately so the playground isn't empty
        -- A couple of custom seams, to show the extension points:
        icon_overrides = { conf = { glyph = "\u{e615}", hl = "NxTreeIconDefault" } },
        mappings = {
          -- Add a binding without redeclaring the defaults: `.` makes the dir under
          -- the cursor the new root (an alias for the built-in `>`).
          ["."] = "change_root",
        },
      })
    end,
  },
})

-- A custom action, registered after setup: `<C-r>` reveals the current file. Shows
-- the register_action seam — `fn(tree, api)` runs inside the async error wrapper.
require("nxvim-tree").register_action("<C-r>", function(_tree, api)
  api.reveal()
end)
