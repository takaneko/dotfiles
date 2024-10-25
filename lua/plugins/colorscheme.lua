return {
  {
    "folke/tokyonight.nvim",
    branch = "main",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd([[colorscheme tokyonight]])
    end,
  },
}
