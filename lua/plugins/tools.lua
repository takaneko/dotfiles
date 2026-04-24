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
    'nvim-telescope/telescope.nvim',
    tag = 'v0.2.2',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
  },
}
