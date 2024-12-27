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

  -- Indent
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    ---@module "ibl"
    ---@type ibl.config
    opts = {},
  },

  -- Golang
  {
    "sebdah/vim-delve",
    ft = "go",
  },
  -- Ruby
  {
    "vim-ruby/vim-ruby",
    ft = "ruby",
  },
  -- Rails
  {
    "tpope/vim-rails",
    ft = { "ruby", "eruby", "haml", "slim" },
  },
  -- HTML
  {
    "mattn/emmet-vim",
    ft = { "html", "css", "javascript", "javascriptreact", "typescript", "typescriptreact" },
  },
  -- CSV
  {
    "mechatroner/rainbow_csv",
    ft = "csv",
  },
  -- SQL
  {
    "vim-scripts/SQLUtilities",
    ft = "sql",
  },
}
