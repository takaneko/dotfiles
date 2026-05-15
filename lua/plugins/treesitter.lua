return {
  {
    -- main ブランチは nvim 0.12+ 用の書き直し版。lazy-load 不可・新APIなので
    -- branch="main" / lazy=false を明示。詳細は CLAUDE.md 参照。
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
  },
  {
    "nvim-treesitter/nvim-treesitter-context",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("treesitter-context").setup()
    end,
  },
  {
    -- TSX/JSX/HTML 等のタグ自動補完。旧 nvim-treesitter master の autotag モジュール
    -- 代替（main では削除されたため別プラグイン化）。
    "windwp/nvim-ts-autotag",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = { "html", "javascript", "typescript", "javascriptreact", "typescriptreact", "tsx", "jsx", "xml", "markdown" },
    config = function()
      require("nvim-ts-autotag").setup()
    end,
  },
}
