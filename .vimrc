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
" color
NeoBundle 'sickill/vim-monokai'
NeoBundle 'januswel/html5.vim'
NeoBundle 'mattn/emmet-vim'
NeoBundle 'kchmck/vim-coffee-script'
NeoBundle 'pangloss/vim-javascript'
NeoBundle 'nathanaelkane/vim-indent-guides'
NeoBundle 'vim-scripts/AnsiEsc.vim'
" check
NeoBundle 'scrooloose/syntastic'
" useful
NeoBundle 'tpope/vim-endwise'
NeoBundle 'tpope/vim-fugitive'
NeoBundle 'tpope/vim-rails'
NeoBundle 'vim-scripts/gtags.vim'
NeoBundle 'vim-jp/vimdoc-ja'
call neobundle#end()

filetype plugin indent on

NeoBundleCheck

" help
set helplang=ja,en

" syntax highlight
colorscheme monokai
syntax on

" tab
set tabstop=2
set autoindent
set expandtab
set shiftwidth=2
" encoding
set encoding=utf-8

" statusline
set laststatus=2

set statusline=%<%f\ %m%r%h%w
set statusline+=%{'['.(&fenc!=''?&fenc:&enc).']['.&fileformat.']'}
set statusline+=%=%l/%L,%c%V%8P

" matchit
source $VIMRUNTIME/macros/matchit.vim

" syntastic
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

" remove trailing space
autocmd BufWritePre * :%s/\s\+$//ge

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_javascript_checkers = ['eslint']

" vim-indent-guides
let g:indent_guides_enable_on_vim_startup = 1
let indent_guides_auto_colors = 0
autocmd VimEnter,Colorscheme * :hi IndentGuidesOdd  guibg=darkgrey   ctermbg=236
autocmd VimEnter,Colorscheme * :hi IndentGuidesEven guibg=darkgrey   ctermbg=237
let indent_guides_color_change_percent = 10

" fugitive
autocmd QuickFixCmdPost *grep* cwindow
set statusline+=%{fugitive#statusline()}
