if &compatible
  set nocompatible               " Be iMproved
endif

set runtimepath+=/Users/nirareba1969/.cache/dein/repos/github.com/Shougo/dein.vim

if dein#load_state('/Users/nirareba1969/.cache/dein')
  call dein#begin('/Users/nirareba1969/.cache/dein')

  call dein#add('/Users/nirareba1969/.cache/dein/repos/github.com/Shougo/dein.vim')

  call dein#add('Shougo/neosnippet.vim')
  call dein#add('Shougo/neosnippet-snippets')
  " color
  call dein#add('sickill/vim-monokai')
  call dein#add('januswel/html5.vim')
  call dein#add('mattn/emmet-vim')
  call dein#add('kchmck/vim-coffee-script')
  call dein#add('pangloss/vim-javascript')
  call dein#add('posva/vim-vue')
  call dein#add('leafgarland/typescript-vim')
  call dein#add('nathanaelkane/vim-indent-guides')
  call dein#add('vim-scripts/AnsiEsc.vim')
  call dein#add('rust-lang/rust.vim')
  call dein#add('fatih/vim-go')
  call dein#add('vim-ruby/vim-ruby')
  call dein#add('hashivim/vim-terraform')
  " check
  call dein#add('scrooloose/syntastic')
  " useful
  call dein#add('tpope/vim-endwise')
  call dein#add('tpope/vim-fugitive')
  call dein#add('tpope/vim-rails')
  call dein#add('vim-scripts/gtags.vim')
  call dein#add('vim-jp/vimdoc-ja')
  call dein#add('jremmen/vim-ripgrep')
  call dein#add('junegunn/fzf.vim')

  call dein#end()
  call dein#save_state()
endif

filetype plugin indent on

if dein#check_install()
  call dein#install()
endif

" help
set helplang=ja,en

" write
set autowrite

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

" let g:syntastic_auto_loc_list = 1
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

" Similarly, we can apply it to fzf#vim#grep. To use ripgrep instead of ag:
" command! -bang -nargs=* Rg
"   \ call fzf#vim#grep(
"   \   'rg --column --line-number --no-heading --color=always '.shellescape(<q-args>), 1,
"   \   <bang>0 ? fzf#vim#with_preview('up:60%')
"   \           : fzf#vim#with_preview('right:50%:hidden', '?'),
"   \   <bang>0)

" vim-ruby
let ruby_fold = 1

" vim-go
let g:go_null_module_warning = 0
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_structs = 1
let g:go_highlight_functions = 1
let g:go_highlight_function_calls = 1
let g:go_def_mode='gopls'
let g:go_info_mode='gopls'
let g:go_fmt_command = "goimports"
au FileType go setlocal sw=4 ts=4 sts=4 noet
filetype plugin indent on
