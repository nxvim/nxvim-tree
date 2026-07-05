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

  -- The sidebar's window chrome (background / cursorline / `~` fillers) is remapped
  -- through the tree window's `winhighlight`. The fallbacks LINK to the editor's own
  -- chrome groups so they follow the theme's light/dark flavour (a hardcoded colour
  -- would go dark under catppuccin-latte). Verify the links, so on a light theme the
  -- tree's fillers/cursorline stay light like the main editor.
  nx.test.it("links window-chrome fallbacks to the editor's themed groups", function()
    highlights.apply({})
    local function link_of(name)
      return nx.hl.get(0, { name = name, link = true }).link
    end
    nx.test.expect(link_of("NvimTreeNormal")).to_be("NormalFloat")
    nx.test.expect(link_of("NvimTreeEndOfBuffer")).to_be("EndOfBuffer")
    nx.test.expect(link_of("NvimTreeCursorLine")).to_be("CursorLine")
    nx.test.expect(link_of("NvimTreeCursorLineNr")).to_be("CursorLineNr")
  end)

  nx.test.it("does NOT overwrite a colorscheme's NvimTreeNormal background", function()
    -- A ported colorscheme (e.g. catppuccin) sets the sidebar bg first; the
    -- fallback must yield so the theme's shade survives regardless of load order.
    nx.hl.define(0, "NvimTreeNormal", { fg = "#cdd6f4", bg = "#222233" })
    highlights.apply({})
    nx.test.expect(nx.hl.get(0, { name = "NvimTreeNormal" }).bg).to_be(0x222233)
  end)
end)
