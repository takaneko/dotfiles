if &compatible
  set nocompatible " Be iMproved
endif

call plug#begin('~/.vim/plugged')

" color
Plug 'crusoexia/vim-monokai'
Plug 'mattn/emmet-vim'
Plug 'moll/vim-node'
Plug 'pangloss/vim-javascript'
Plug 'maxmellon/vim-jsx-pretty'
Plug 'prettier/vim-prettier', { 'for': ['javascript', 'typescript', 'css', 'scss', 'json', 'markdown', 'vue', 'html', 'graphql'] }
Plug 'posva/vim-vue'
Plug 'leafgarland/typescript-vim'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'vim-scripts/AnsiEsc.vim'
Plug 'rust-lang/rust.vim'
Plug 'fatih/vim-go'
Plug 'vim-ruby/vim-ruby'
Plug 'pocke/rbs.vim'
Plug 'hashivim/vim-terraform'
Plug 'dart-lang/dart-vim-plugin'
Plug 'slim-template/vim-slim'
Plug 'tpope/vim-haml'
Plug 'mechatroner/rainbow_csv'
Plug 'etdev/vim-hexcolor'
Plug 'plasticboy/vim-markdown'
Plug 'styled-components/vim-styled-components', { 'branch': 'main' }
Plug 'cespare/vim-toml'
Plug 'jparise/vim-graphql'
" check
Plug 'scrooloose/syntastic'
" useful
Plug 'tpope/vim-endwise'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-rails'
Plug 'vim-scripts/gtags.vim'
Plug 'vim-jp/vimdoc-ja'
Plug 'jremmen/vim-ripgrep'
Plug 'junegunn/fzf', {'build': './install --all'}
Plug 'junegunn/fzf.vim'
Plug 'godlygeek/tabular'
Plug 'vim-scripts/Align'
Plug 'vim-scripts/SQLUtilities'
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/asyncomplete-lsp.vim'
Plug 'prabirshrestha/vim-lsp'
Plug 'mattn/vim-lsp-settings'

call plug#end()

packloadall
filetype plugin indent on

autocmd bufnewfile,bufread *.tsx set filetype=typescript.tsx
autocmd bufnewfile,bufread *.jsx set filetype=javascript.jsx
autocmd bufnewfile,bufread Steepfile set filetype=ruby

" help
set helplang=ja,en

" write
set autowrite

" syntax highlight
colorscheme monokai
syntax on

highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$/

" tab
set tabstop=2
set autoindent
set expandtab
set shiftwidth=2
" encoding
set encoding=utf-8
set fileencodings=utf-8

" fold
set foldenable
set foldlevelstart=1
set foldmethod=indent

set synmaxcol=256
syntax sync minlines=256

" Don't screw up folds when inserting text that might affect them, until
" leaving insert mode. Foldmethod is local to the window. Protect against
" screwing up folding when switching between windows.
autocmd InsertEnter * if !exists('w:last_fdm') | let w:last_fdm=&foldmethod | setlocal foldmethod=manual | endif
autocmd InsertLeave,WinLeave * if exists('w:last_fdm') | let &l:foldmethod=w:last_fdm | unlet w:last_fdm | endif

" statusline
set laststatus=2

set statusline=%<%f\ %m%r%h%w
set statusline+=%{'['.(&fenc!=''?&fenc:&enc).']['.&fileformat.']'}
set statusline+=%=%l/%L,%c%V%8P

" leader
let mapleader = "\<Space>"

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
autocmd VimEnter,Colorscheme * :hi StatusLine       ctermfg=231 ctermbg=241 cterm=bold guifg=#f8f8f2 guibg=#64645e gui=bold
let indent_guides_color_change_percent = 10

" fugitive
autocmd QuickFixCmdPost *grep* cwindow
set statusline+=%{fugitive#statusline()}

" vim-markdown
let g:vim_markdown_folding_disabled=1

" ripgrep
if executable('rg')
    set grepprg=rg\ --vimgrep\ --no-heading
    set grepformat=%f:%l:%c:%m,%f:%l:%m
endif

" Similarly, we can apply it to fzf#vim#grep. To use ripgrep instead of ag:
command! -bang -nargs=* Rg
  \ call fzf#vim#grep(
  \   'rg --column --line-number --no-heading --color=always '.shellescape(<q-args>), 1,
  \   <bang>0 ? fzf#vim#with_preview('up:60%')
  \           : fzf#vim#with_preview('right:50%:hidden', '?'),
  \   <bang>0)

" vim-local
augroup vimrc-local
  autocmd!
  autocmd BufNewFile,BufReadPost * call s:vimrc_local(expand('<afile>:p:h'))
augroup END

function! s:vimrc_local(loc)
  let files = findfile('.vimrc.local', escape(a:loc, ' ') . ';', -1)
  for i in reverse(filter(files, 'filereadable(v:val)'))
    source `=i`
  endfor
endfunction

" vim-ruby
let ruby_fold = 1

" vim-lsp
function! s:on_lsp_buffer_enabled() abort
    setlocal omnifunc=lsp#complete
    setlocal signcolumn=yes
    nmap <buffer> gd <plug>(lsp-definition)
    nmap <buffer> gr <plug>(lsp-references)
    nmap <buffer> gi <plug>(lsp-implementation)
    nmap <buffer> gt <plug>(lsp-type-definition)
    nmap <buffer> <leader>rn <plug>(lsp-rename)
    nmap <buffer> [g <Plug>(lsp-previous-diagnostic)
    nmap <buffer> ]g <Plug>(lsp-next-diagnostic)
    nmap <buffer> K <plug>(lsp-hover)

    " refer to doc to add more commands
endfunction

augroup lsp_install
    au!
    " call s:on_lsp_buffer_enabled only for languages that has the server registered.
    autocmd User lsp_buffer_enabled call s:on_lsp_buffer_enabled()
augroup END

" vim-go
let g:go_gopls_enabled = 0
let g:go_null_module_warning = 0
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_structs = 1
let g:go_highlight_functions = 1
let g:go_highlight_function_calls = 1
let g:go_auto_type_info = 1
let g:go_fmt_command = "goimports"
au FileType go setlocal sw=4 ts=4 sts=4 noet
filetype plugin indent on

" vim-lsp
let g:lsp_log_verbose = 0
let g:lsp_log_file = expand('~/vim-lsp.log')

let g:lsp_settings_filetype_ruby = ['steep', 'solargraph']

" vim-lsp-settings
let g:lsp_settings = {
      \ 'tailwindcss-intellisense': {
        \ 'allowlist': ['html', 'css', 'eruby']
        \ }
\ }

" vim-jsx-pretty
let g:vim_jsx_pretty_colorful_config=1

" vim-prettier
let g:prettier#autoformat = 1
let g:prettier#autoformat_require_pragma = 0
let g:prettier#config#end_of_line = get(g:, 'prettier#config#end_of_line', 'lf')
