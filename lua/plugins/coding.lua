return {
  -- LSP and Completion
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
  -- CSS
  {
    'brenoprata10/nvim-highlight-colors',
    config = function()
      require('nvim-highlight-colors').setup({
        enable_tailwind = true,
      })
    end,
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
