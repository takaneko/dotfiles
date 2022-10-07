set runtimepath+=$HOME/dotfiles

call plug#begin('~/.nvim/plugged')
runtime! vim/plugin.vim
call plug#end()

runtime! vim/basic.vim
runtime! vim/plugsettings.vim
