return {
  "saghen/blink.cmp",
  opts = {
    completion = {
      -- No dropdown unless you ask for it with <C-space>
      menu = { auto_show = false },

      -- No inline virtual-text preview
      ghost_text = { enabled = false },

      -- Docs window only on demand
      documentation = { auto_show = false },

      -- When you DO open the menu, nothing is selected or inserted
      -- until you deliberately pick an item
      list = {
        selection = { preselect = false, auto_insert = false },
      },
    },

    -- The half worth keeping: parameter lists while you're inside the parens
    signature = {
      enabled = true,
      window = { show_documentation = false },
    },

    -- Real symbol info only — no "this word appears elsewhere in the file"
    sources = {
      default = { "lsp", "path" },
    },
  },
}
