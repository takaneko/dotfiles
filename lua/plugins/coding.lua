return {
  -- LSP and Completion
  {
    "neoclide/coc.nvim",
    branch = "release",
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/nvim-cmp",
    },
  },
  {
    "github/copilot.vim",
    event = "InsertEnter",
  },
  {
    "dense-analysis/ale",
    event = { "BufReadPre", "BufNewFile" },
  },

  -- Language specific
  {
    "tpope/vim-rails",
    ft = { "ruby", "eruby", "haml", "slim" },
  },
  {
    "mattn/emmet-vim",
    ft = { "html", "css", "javascript", "javascriptreact", "typescript", "typescriptreact" },
  },
}
