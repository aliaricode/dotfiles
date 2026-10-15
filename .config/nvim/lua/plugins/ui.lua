return {

  -- This adds the 'surround' keybinds
  {
    "kylechui/nvim-surround",
    version = "*", -- Use latest stable release
    config = function()
      require("nvim-surround").setup({
        -- Configuration goes here
      })
    end,
  },
}
