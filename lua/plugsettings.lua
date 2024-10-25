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
vim.keymap.set('n', '<leader>g', ':Rg <c-r><c-w><cr>')

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

-- coc-nvim basic settings
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.updatetime = 300
vim.opt.signcolumn = 'yes'

-- coc-nvim functions
local function check_backspace()
  local col = vim.fn.col('.') - 1
  return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s')
end

local function show_documentation()
  if vim.fn['CocAction']('hasProvider', 'hover') then
    vim.fn['CocActionAsync']('doHover')
  else
    vim.api.nvim_feedkeys('K', 'in', true)
  end
end

-- coc-nvim keymaps
local keyset = vim.keymap.set
keyset('i', '<TAB>', function()
  return vim.fn['coc#pum#visible']() == 1 and vim.fn['coc#pum#next'](1)
    or check_backspace() and '<TAB>'
    or vim.fn['coc#refresh']()
end, { silent = true, expr = true })
keyset('i', '<S-TAB>', function()
  return vim.fn['coc#pum#visible']() == 1 and vim.fn['coc#pum#prev'](1) or '<C-h>'
end, { expr = true })
keyset('i', '<cr>', function()
  return vim.fn['coc#pum#visible']() == 1 and vim.fn['coc#pum#confirm']()
    or string.format('<C-g>u<CR><c-r>=%s<CR>', vim.fn['coc#on_enter']())
end, { silent = true, expr = true })

-- coc-nvim completion trigger
if vim.fn.has('nvim') == 1 then
  keyset('i', '<c-space>', 'coc#refresh()', { silent = true, expr = true })
else
  keyset('i', '<c-@>', 'coc#refresh()', { silent = true, expr = true })
end

-- coc-nvim navigation
keyset('n', '[g', '<Plug>(coc-diagnostic-prev)', { silent = true })
keyset('n', ']g', '<Plug>(coc-diagnostic-next)', { silent = true })
keyset('n', 'gd', '<Plug>(coc-definition)', { silent = true })
keyset('n', 'gy', '<Plug>(coc-type-definition)', { silent = true })
keyset('n', 'gi', '<Plug>(coc-implementation)', { silent = true })
keyset('n', 'gr', '<Plug>(coc-references)', { silent = true })
keyset('n', 'K', show_documentation, { silent = true })

-- coc-nvim highlights and actions
vim.api.nvim_create_autocmd('CursorHold', {
  callback = function()
    vim.fn['CocActionAsync']('highlight')
  end,
  pattern = '*'
})

-- coc-nvim mappings
keyset('n', '<leader>rn', '<Plug>(coc-rename)')
keyset('x', '<leader>f', '<Plug>(coc-format-selected)')
keyset('n', '<leader>f', '<Plug>(coc-format-selected)')

-- coc-nvim autocommands
local coc_group = vim.api.nvim_create_augroup('mygroup', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = coc_group,
  pattern = { 'typescript', 'json' },
  command = 'setl formatexpr=CocAction("formatSelected")'
})
vim.api.nvim_create_autocmd('User', {
  group = coc_group,
  pattern = 'CocJumpPlaceholder',
  command = 'call CocActionAsync("showSignatureHelp")'
})

-- coc-nvim code actions
keyset('x', '<leader>a', '<Plug>(coc-codeaction-selected)')
keyset('n', '<leader>a', '<Plug>(coc-codeaction-selected)')
keyset('n', '<leader>ac', '<Plug>(coc-codeaction-cursor)')
keyset('n', '<leader>as', '<Plug>(coc-codeaction-source)')
keyset('n', '<leader>qf', '<Plug>(coc-fix-current)')
keyset('n', '<leader>re', '<Plug>(coc-codeaction-refactor)', { silent = true })
keyset('x', '<leader>r', '<Plug>(coc-codeaction-refactor-selected)', { silent = true })
keyset('n', '<leader>r', '<Plug>(coc-codeaction-refactor-selected)', { silent = true })
keyset('n', '<leader>cl', '<Plug>(coc-codelens-action)')

-- coc-nvim text objects
for _, mode in ipairs({ 'x', 'o' }) do
  keyset(mode, 'if', '<Plug>(coc-funcobj-i)')
  keyset(mode, 'af', '<Plug>(coc-funcobj-a)')
  keyset(mode, 'ic', '<Plug>(coc-classobj-i)')
  keyset(mode, 'ac', '<Plug>(coc-classobj-a)')
end

-- coc-nvim scroll float windows
if vim.fn.has('nvim-0.4.0') == 1 or vim.fn.has('patch-8.2.0750') == 1 then
  for _, mode in ipairs({ 'n', 'v' }) do
    keyset(mode, '<C-f>', [[coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"]], { silent = true, nowait = true, expr = true })
    keyset(mode, '<C-b>', [[coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"]], { silent = true, nowait = true, expr = true })
  end
  keyset('i', '<C-f>', [[coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"]], { silent = true, nowait = true, expr = true })
  keyset('i', '<C-b>', [[coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"]], { silent = true, nowait = true, expr = true })
end

-- coc-nvim selection ranges
keyset('n', '<C-s>', '<Plug>(coc-range-select)', { silent = true })
keyset('x', '<C-s>', '<Plug>(coc-range-select)', { silent = true })

-- coc-nvim commands
vim.api.nvim_create_user_command('Format', 'call CocActionAsync("format")', {})
vim.api.nvim_create_user_command('Fold', 'call CocAction("fold", <f-args>)', { nargs = '?' })
vim.api.nvim_create_user_command('OR', 'call CocActionAsync("runCommand", "editor.action.organizeImport")', {})

-- coc-nvim CoCList mappings
local coclist_mappings = {
  { key = 'a', cmd = 'CocList diagnostics' },
  { key = 'e', cmd = 'CocList extensions' },
  { key = 'c', cmd = 'CocList commands' },
  { key = 'o', cmd = 'CocList outline' },
  { key = 's', cmd = 'CocList -I symbols' },
  { key = 'j', cmd = 'CocNext' },
  { key = 'k', cmd = 'CocPrev' },
  { key = 'p', cmd = 'CocListResume' }
}

for _, mapping in ipairs(coclist_mappings) do
  keyset('n', '<space>' .. mapping.key, ':' .. mapping.cmd .. '<cr>', { silent = true, nowait = true })
end

-- indentLine
vim.api.nvim_create_autocmd('InsertEnter', {
  command = 'setlocal concealcursor='
})
vim.api.nvim_create_autocmd('InsertLeave', {
  command = 'setlocal concealcursor=inc'
})
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    vim.g.indentLine_setConceal = 0
  end
})

-- coc-go
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*.go',
  command = 'OR'
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'go',
  callback = function()
    vim.keymap.set('n', 'gtj', ':CocCommand go.tags.add json<cr>')
    vim.keymap.set('n', 'gty', ':CocCommand go.tags.add yaml<cr>')
    vim.keymap.set('n', 'gtx', ':CocCommand go.tags.clear<cr>')
    vim.opt_local.sw = 4
    vim.opt_local.ts = 4
    vim.opt_local.sts = 4
    vim.opt_local.expandtab = false
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

-- ale
vim.g.ale_fixers = {
  ruby = { 'rubocop' },
  typescript = { 'prettier', 'eslint', 'biome' },
  typescriptreact = { 'prettier', 'eslint', 'biome' },
  javascript = { 'prettier', 'eslint' },
  javascriptreact = { 'prettier', 'eslint' },
  css = { 'prettier', 'eslint' }
}
vim.g.ale_linters_explicit = 1
vim.g.airline_extensions_ale_enabled = 1
vim.g.ale_fix_on_save = 1
vim.g.ale_javascript_prettier_use_local_config = 1

vim.api.nvim_create_user_command('ALEToggleFixer', function()
  vim.g.ale_fix_on_save = not vim.g.ale_fix_on_save
end, {})
