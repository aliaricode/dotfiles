return {
  -- This file overrides the default LazyVim plugin spec
  {
    "LazyVim/LazyVim",
    opts = {
      -- This changes the default colorscheme from 'tokyonight'
      colorscheme = "neopywal",
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          -- This tells the linter to use your global config
          args = { "--config", vim.fn.expand("~/.markdownlint-cli2.jsonc"), "--" },
        },
      },
    },
  },
}
