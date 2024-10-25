-- runtimepathの設定
vim.opt.runtimepath:append(vim.fn.expand("$HOME/dotfiles"))

local dotfiles = vim.fn.expand("$HOME/dotfiles")
package.path = package.path .. ";" .. dotfiles .. "/lua/?.lua"

-- vim-plugの初期化（vim-plugを継続して使用する場合）
-- local Plug = vim.fn['plug#']

-- vim.call('plug#begin', '~/.nvim/plugged')
-- -- plugin.vimの読み込み
-- vim.cmd('runtime! vim/plugin.vim')
-- vim.call('plug#end')

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Setup lazy.nvim
require("lazy").setup({
  spec = {
    -- import your plugins
    { import = "plugins" },
  },
})

-- 他の設定ファイルの読み込み
-- vim.cmd('runtime! vim/basic.vim')
require('config.basic')
-- vim.cmd('runtime! vim/plugsettings.vim')
require('config.plugsettings')
