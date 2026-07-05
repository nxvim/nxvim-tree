-- The highlight contract: the explorer uses the canonical NvimTree* group names, and
-- defines them only as a FALLBACK so a ported colorscheme (e.g. catppuccin-nxvim,
-- which styles NvimTree*) themes the tree unmodified. Run with `nxvim --test-plugin`.

local highlights = require("nxvim-tree.highlights")

-- The structural / git groups a colorscheme is expected to own.
local CANONICAL = {
  "NvimTreeRootFolder",
  "NvimTreeFolderName",
  "NvimTreeOpenedFolderName",
  "NvimTreeEmptyFolderName",
  "NvimTreeFolderIcon",
  "NvimTreeIndentMarker",
  "NvimTreeSymlink",
  "NvimTreeOpenedFile",
  "NvimTreeSpecialFile",
  "NvimTreeImageFile",
  "NvimTreeGitNew",
  "NvimTreeGitDirty",
  "NvimTreeGitStaged",
  "NvimTreeGitDeleted",
}

nx.test.describe("nxvim-tree.highlights", function()
  nx.test.it("defines the canonical NvimTree* groups", function()
    highlights.apply({})
    for _, name in ipairs(CANONICAL) do
      nx.test.expect(nx.hl.exists(name)).to_be_truthy()
    end
  end)

  -- nx.hl.get returns `fg` as a decimal integer (0xRRGGBB), so compare numerically.
  nx.test.it("does NOT overwrite a group a colorscheme already defined", function()
    -- Simulate the colorscheme defining its NvimTree* color first.
    nx.hl.define(0, "NvimTreeFolderName", { fg = "#abcdef" })
    highlights.apply({})
    -- The fallback must have yielded — the colorscheme's color survives.
    nx.test.expect(nx.hl.get(0, { name = "NvimTreeFolderName" }).fg).to_be(0xabcdef)
  end)

  nx.test.it("honors an explicit user override over the fallback", function()
    highlights.apply({ NvimTreeRootFolder = { fg = "#123456" } })
    nx.test.expect(nx.hl.get(0, { name = "NvimTreeRootFolder" }).fg).to_be(0x123456)
  end)

  -- The sidebar's window chrome (background / cursorline / hidden `~` fillers) is
  -- remapped through the tree window's `winhighlight`, so these groups must exist
  -- and — unlike the fg-only text groups — carry a background.
  nx.test.it("defines window-chrome fallbacks with a background", function()
    highlights.apply({})
    for _, name in ipairs({
      "NvimTreeNormal",
      "NvimTreeEndOfBuffer",
      "NvimTreeCursorLine",
      "NvimTreeCursorLineNr",
    }) do
      nx.test.expect(nx.hl.exists(name)).to_be_truthy()
    end
    -- NvimTreeNormal is the darker sidebar background — it must define `bg`.
    nx.test.expect(nx.hl.get(0, { name = "NvimTreeNormal" }).bg).to_be(0x181825)
  end)

  nx.test.it("does NOT overwrite a colorscheme's NvimTreeNormal background", function()
    -- A ported colorscheme (e.g. catppuccin) sets the sidebar bg first; the
    -- fallback must yield so the theme's shade survives regardless of load order.
    nx.hl.define(0, "NvimTreeNormal", { fg = "#cdd6f4", bg = "#222233" })
    highlights.apply({})
    nx.test.expect(nx.hl.get(0, { name = "NvimTreeNormal" }).bg).to_be(0x222233)
  end)
end)
