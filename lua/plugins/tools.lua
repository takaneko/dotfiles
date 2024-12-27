return {
  -- Documentation
  {
    "vim-jp/vimdoc-ja",
    lazy = false,
  },

  -- Git
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "Gwrite", "Gcommit", "Gread" },
  },

  -- Navigation and Search
  {
    "junegunn/fzf",
    build = "./install --all",
  },
  {
    "junegunn/fzf.vim",
    dependencies = { "junegunn/fzf" },
    cmd = { "Files", "GFiles", "Buffers", "Rg" },
  },
  {
    "zackhsi/fzf-tags",
    dependencies = { "junegunn/fzf.vim" },
  },
  {
    "vim-scripts/gtags.vim",
    cmd = { "Gtags" },
  },
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
  },
  {
    'nvim-telescope/telescope-fzf-native.nvim',
    build = 'make'
  },

  -- Code helpers
  {
    "godlygeek/tabular",
    cmd = { "Tabularize" },
  },
  {
    "vim-scripts/Align",
    cmd = { "Align" },
  },
}
