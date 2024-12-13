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
