-- パッケージとファイルタイプの設定
vim.cmd('packloadall')
vim.cmd('filetype plugin indent on')

-- Steepfileのファイルタイプ設定
vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
  pattern = "Steepfile",
  command = "set filetype=ruby"
})

-- フォールディングの保護設定
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    if vim.w.last_fdm == nil then
      vim.w.last_fdm = vim.wo.foldmethod
      vim.wo.foldmethod = "manual"
    end
  end
})

vim.api.nvim_create_autocmd({"InsertLeave", "WinLeave"}, {
  callback = function()
    if vim.w.last_fdm ~= nil then
      vim.wo.foldmethod = vim.w.last_fdm
      vim.w.last_fdm = nil
    end
  end
})

-- ヘルプ言語設定
vim.opt.helplang = "ja,en"

-- 自動保存設定
vim.opt.autowrite = true

-- シンタックスハイライトとカラースキーム
vim.cmd('colorscheme tokyonight')
vim.cmd('syntax on')

-- 行番号とスペースのハイライト設定
vim.api.nvim_set_hl(0, 'LineNr', { fg = 'white' })
vim.api.nvim_set_hl(0, 'ExtraWhitespace', { bg = 'red' })
vim.cmd('match ExtraWhitespace /\\s\\+$/')

-- タブとインデント設定
vim.opt.tabstop = 2
vim.opt.autoindent = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2

-- エンコーディング設定
vim.opt.encoding = 'utf-8'
vim.opt.fileencodings = 'utf-8'

-- フォールディング設定
vim.opt.foldenable = true
vim.opt.foldlevelstart = 1
vim.opt.foldmethod = 'indent'

-- シンタックス設定
vim.opt.synmaxcol = 256
vim.cmd('syntax sync minlines=256')

-- vim-indent-guides設定
vim.g.indent_guides_enable_on_vim_startup = 1
vim.g.indent_guides_auto_colors = 0

-- インデントガイドとステータスラインの色設定
vim.api.nvim_create_autocmd({"VimEnter", "Colorscheme"}, {
  callback = function()
    vim.api.nvim_set_hl(0, 'IndentGuidesOdd', { bg = 'darkgrey', ctermbg = 236 })
    vim.api.nvim_set_hl(0, 'IndentGuidesEven', { bg = 'darkgrey', ctermbg = 237 })
    vim.api.nvim_set_hl(0, 'StatusLine', {
      ctermfg = 231,
      ctermbg = 241,
      bold = true,
      fg = '#f8f8f2',
      bg = '#64645e'
    })
  end
})

vim.g.indent_guides_color_change_percent = 10

-- ステータスライン設定
vim.opt.laststatus = 2

-- リーダーキー設定
vim.g.mapleader = " "
