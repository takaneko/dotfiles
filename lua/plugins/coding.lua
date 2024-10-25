return {
  -- LSP and Completion
  {
    "neoclide/coc.nvim",
    branch = "release",
    event = { "BufReadPre", "BufNewFile" },
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
    "maxmellon/vim-jsx-pretty",
    ft = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  },
  {
    "tpope/vim-rails",
    ft = { "ruby", "eruby", "haml", "slim" },
  },
  {
    "mattn/emmet-vim",
    ft = { "html", "css", "javascript", "javascriptreact", "typescript", "typescriptreact" },
  },
}
