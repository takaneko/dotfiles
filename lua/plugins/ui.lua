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
    "Yggdroot/indentLine",
    event = { "BufReadPre", "BufNewFile" },
  },
}
