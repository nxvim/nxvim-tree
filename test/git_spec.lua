-- Git porcelain → sign classification. Pure, run with `nxvim --test-plugin`.

local git = require("nxvim-tree.git")

-- The hl groups are the canonical NvimTree* names so a ported colorscheme themes them.
nx.test.describe("nxvim-tree.git.classify", function()
  nx.test.it("marks untracked files as new", function()
    nx.test.expect(git.classify("??").hl).to_be("NvimTreeGitNew")
  end)

  nx.test.it("marks a working-tree modification as dirty", function()
    nx.test.expect(git.classify(" M").hl).to_be("NvimTreeGitDirty")
  end)

  nx.test.it("marks a staged-only change as staged", function()
    nx.test.expect(git.classify("M ").hl).to_be("NvimTreeGitStaged")
  end)

  nx.test.it("marks a deletion in either column", function()
    nx.test.expect(git.classify(" D").hl).to_be("NvimTreeGitDeleted")
    nx.test.expect(git.classify("D ").hl).to_be("NvimTreeGitDeleted")
  end)

  nx.test.it("marks an addition", function()
    nx.test.expect(git.classify("A ").hl).to_be("NvimTreeGitNew")
  end)
end)
