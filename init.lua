-- runtimepathの設定
vim.opt.runtimepath:append(vim.fn.expand("$HOME/dotfiles"))

local dotfiles = vim.fn.expand("$HOME/dotfiles")
package.path = package.path .. ";" .. dotfiles .. "/lua/?.lua"

-- vim-plugの初期化（vim-plugを継続して使用する場合）
local Plug = vim.fn['plug#']

vim.call('plug#begin', '~/.nvim/plugged')
-- plugin.vimの読み込み
vim.cmd('runtime! vim/plugin.vim')
vim.call('plug#end')

-- 他の設定ファイルの読み込み
-- vim.cmd('runtime! vim/basic.vim')
require('config.basic')
-- vim.cmd('runtime! vim/plugsettings.vim')
require('config.plugsettings')
