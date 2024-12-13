-- matchit
vim.cmd('source $VIMRUNTIME/macros/matchit.vim')

-- fugitive
vim.api.nvim_create_autocmd('QuickFixCmdPost', {
  pattern = '*grep*',
  command = 'cwindow'
})

-- vim-markdown
vim.g.vim_markdown_folding_disabled = 1

-- ripgrep
if vim.fn.executable('rg') == 1 then
  vim.opt.grepprg = 'rg --vimgrep --no-heading'
  vim.opt.grepformat = '%f:%l:%c:%m,%f:%l:%m'
end

-- fzf
vim.keymap.set('n', '<leader>t', ':Tags <c-r><c-w><cr>')

-- Mapping selecting mappings
vim.keymap.set('n', '<leader><tab>', '<plug>(fzf-maps-n)')
vim.keymap.set('x', '<leader><tab>', '<plug>(fzf-maps-x)')
vim.keymap.set('o', '<leader><tab>', '<plug>(fzf-maps-o)')

-- Insert mode completion
vim.keymap.set('i', '<c-x><c-k>', '<plug>(fzf-complete-word)')
vim.keymap.set('i', '<c-x><c-f>', '<plug>(fzf-complete-path)')
vim.keymap.set('i', '<c-x><c-l>', '<plug>(fzf-complete-line)')

-- Path completion with custom source command
vim.cmd([[
inoremap <expr> <c-x><c-f> fzf#vim#complete#path('fd')
inoremap <expr> <c-x><c-f> fzf#vim#complete#path('rg --files')
]])

-- Word completion with custom spec with popup layout option
vim.cmd([[
inoremap <expr> <c-x><c-k> fzf#vim#complete#word({'window': { 'width': 0.2, 'height': 0.9, 'xoffset': 1 }})
]])

-- Global line completion
vim.cmd([[
inoremap <expr> <c-x><c-l> fzf#vim#complete(fzf#wrap({
  \ 'prefix': '^.*$',
  \ 'source': 'rg -n ^ --color always',
  \ 'options': '--ansi --delimiter : --nth 3..',
  \ 'reducer': { lines -> join(split(lines[0], ':\zs')[2:], '') }}))
]])

-- fzf-tags
vim.cmd("noreabbrev <expr> ts getcmdtype() == ':' && getcmdline() == 'ts' ? 'FZFTselect' : 'ts'")

-- vim-ruby
vim.g.ruby_fold = 1

-- vim-jsx-pretty
vim.g.vim_jsx_pretty_colorful_config = 1

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

-- mdx
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
  pattern = '*.mdx',
  command = 'setfiletype markdown.mdx'
})

-- inky
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
  pattern = '*.inky',
  command = 'setfiletype eruby'
})
