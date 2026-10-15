return {
  -- 1. neopywal: a theme built on the palette wallust writes to
  --    ~/.cache/wallust/colors_neopywal.vim (template: colors_neopywal.vim).
  --    It watches that file, so open Neovim windows repaint by themselves
  --    whenever the wallpaper / theme changes.
  {
    "RedsXDD/neopywal.nvim",
    name = "neopywal",
    lazy = false,
    priority = 1000,
    opts = {
      use_palette = "wallust",
      -- Leave the background to the terminal, so Alacritty's opacity applies.
      transparent_background = true,
      -- neopywal paints strings in the plain foreground; give them their own slot.
      custom_colors = function(C)
        return { all = { string = C.color3 } }
      end,
      plugins = {
        -- Off by default in neopywal, but LazyVim uses all of these.
        snacks = { enabled = true },
        trouble = true,
        grug_far = true,
        markdown = true, -- render-markdown.nvim (lang.markdown extra)
      },
    },
  },

  -- 2. Statusline and bufferline need neopywal's own hooks.
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      require("neopywal.theme.plugins.lualine").setup()
      opts.options.theme = "neopywal"
    end,
  },
  {
    "akinsho/bufferline.nvim",
    optional = true,
    opts = function(_, opts)
      -- A function, not a table: bufferline calls it again on every
      -- :colorscheme, so the tabs follow neopywal's live reloads.
      opts.highlights = function()
        return require("neopywal.theme.plugins.bufferline").setup({
          -- neopywal keeps the tab bar's fill solid; keep it transparent too.
          fill = { bg = "NONE" },
        })
      end
    end,
  },

  -- 3. Disable the default tokyonight theme
  { "folke/tokyonight.nvim", lazy = true },
}
