require("ibl").setup()
vim.api.nvim_create_user_command('IndentBlanklineToggle', function()
  require('ibl').setup_buffer(0, {
    enabled = not require("ibl.config").get_config(0).enabled,
  })
end, {})
