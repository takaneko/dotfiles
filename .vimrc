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
NeoBundle 'sickill/vim-monokai'
NeoBundle 'tpope/vim-rails'
NeoBundle 'rust-lang/rust.vim'
NeoBundle 'tpope/vim-endwise'
NeoBundle 'kchmck/vim-coffee-script'
NeoBundle 'scrooloose/syntastic'
call neobundle#end()

filetype plugin indent on

NeoBundleCheck

colorscheme monokai
syntax on

set tabstop=2
set autoindent
set expandtab
set shiftwidth=2

set encoding=utf-8

source $VIMRUNTIME/macros/matchit.vim

" syntastic
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_javascript_checkers = ['eslint']
