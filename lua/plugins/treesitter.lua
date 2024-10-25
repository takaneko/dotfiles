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

          -- Ruby関連
          "ruby",        -- Ruby

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
        auto_install = true,

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

      -- TreeSitterを使用したFoldingの設定
      vim.opt.foldmethod = "expr"
      vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
      vim.opt.foldenable = false  -- 初期状態では折りたたみを無効化

      -- ファイルタイプごとの追加設定
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "ruby", "eruby" },
        callback = function()
          -- Rubyのブロック内でのインデントを改善
          vim.opt_local.indentkeys:append("=end,=elsif,=when,=ensure,=rescue,=else,=end")
        end,
      })
    end,
  },
}
