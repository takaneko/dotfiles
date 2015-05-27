if !1 | finish | endif

if has('vim_starting')
  if &compatible
    set nocompatible
  endif

  set runtimepath+=~/.vim/bundle/neobundle.vim/
endif

call neobundle#begin(expand('~/.vim/bundle'))
NeoBundleFetch 'Shougo/neobundle.vim'
call neobundle#end()

call neobundle#begin(expand('~/.vim/bundle'))
NeoBundle 'tomasr/molokai'
call neobundle#end()

filetype plugin indent on

NeoBundleCheck

colorscheme molokai
syntax on

set tabstop=2
set autoindent
set expandtab
set shiftwidth=2

set encoding=utf-8
