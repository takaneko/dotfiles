return {
  {
    "vim-airline/vim-airline",
    dependencies = { "vim-airline/vim-airline-themes" },
  },
  {
    "vim-scripts/AnsiEsc.vim",
  },
  {
    "mechatroner/rainbow_csv",
    ft = "csv",
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    ---@module "ibl"
    ---@type ibl.config
    opts = {},
  }
}
