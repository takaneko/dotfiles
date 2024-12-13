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
