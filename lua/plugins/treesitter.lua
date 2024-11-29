return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "nvim-treesitter/playground",
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      require('nvim-treesitter.configs').setup {
        -- インストールする言語パーサー
        ensure_installed = {
          -- Go関連
          "go",          -- Go言語
          "gomod",       -- Go modules
          "gowork",      -- Go workspace

          -- 設定ファイル関連
          "lua",         -- Neovim設定用
          "vim",         -- Vim script
          "query",       -- TreeSitter queries

          -- Web開発関連（補助）
          "html",        -- HTML
          "css",         -- CSS
          "json",        -- JSON
          "yaml",        -- YAML
        },

        -- 自動インストール
        auto_install = false,

        -- ハイライトの設定
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },

        -- インデントの設定
        indent = {
          enable = true,
        },

        -- インクリメンタルな選択機能
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "gnn",
            node_incremental = "grn",
            scope_incremental = "grc",
            node_decremental = "grm",
          },
        },

        -- 自動タグクローズ（JSX/TSX用）
        autotag = {
          enable = true,
        },
      }
    end,
  },
}