return {
  -- Documentation
  {
    "vim-jp/vimdoc-ja",
    lazy = false,
    -- :helptags regenerates doc/tags-ja without upstream's !_TAG_FILE_ENCODING
    -- header, leaving the working tree dirty and blocking future :Lazy
    -- restore/update. Re-check out the file after lazy's plugin.docs step so
    -- the tree stays clean.
    build = "git checkout -- doc/tags-ja",
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
