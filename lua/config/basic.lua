-- パッケージとファイルタイプの設定
vim.cmd('packloadall')
vim.cmd('filetype plugin indent on')

-- ヘルプ言語設定
vim.opt.helplang = "ja,en"

-- シンタックスハイライトとカラースキーム
vim.cmd('colorscheme tokyonight')
vim.cmd('syntax on')

-- シンタックス設定
vim.opt.synmaxcol = 256
vim.cmd('syntax sync minlines=256')

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

-- 自動保存設定
vim.opt.autowrite = true

-- ステータスライン設定
vim.opt.laststatus = 2

-- リーダーキー設定
vim.g.mapleader = " "

-- keymap
vim.keymap.set('n', '<leader>di', vim.diagnostic.open_float, {noremap=true, silent=true})

-- ripgrep
if vim.fn.executable('rg') == 1 then
  vim.opt.grepprg = 'rg --vimgrep --no-heading'
  vim.opt.grepformat = '%f:%l:%c:%m,%f:%l:%m'
end

-- vim-local
vim.api.nvim_create_augroup('vimrc-local', { clear = true })
vim.api.nvim_create_autocmd({'BufNewFile', 'BufReadPost'}, {
  group = 'vimrc-local',
  callback = function()
    local function vimrc_local(loc)
      local files = vim.fn.findfile('.vimrc.local', vim.fn.escape(loc, ' ') .. ';', -1)
      for _, file in ipairs(vim.fn.reverse(vim.tbl_filter(function(f)
        return vim.fn.filereadable(f) == 1
      end, files))) do
        vim.cmd('source ' .. file)
      end
    end
    vimrc_local(vim.fn.expand('<afile>:p:h'))
  end
})

-- Steepfileのファイルタイプ設定
vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
  pattern = "Steepfile",
  command = "set filetype=ruby"
})

-- mdx
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
  pattern = '*.mdx',
  command = 'setfiletype mdx'
})

-- inky
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
  pattern = '*.inky',
  command = 'setfiletype eruby'
})
