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

NeoBundle 'sickill/vim-monokai'

filetype plugin indent on

NeoBundleCheck

colorscheme monokai
syntax on

set tabstop=2
set autoindent
set expandtab
set shiftwidth=2
