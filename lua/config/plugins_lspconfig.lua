local lspconfig = require("lspconfig")
local cmp_nvim_lsp = require("cmp_nvim_lsp")
local builtin = require("telescope.builtin")

-- キーマッピングの設定
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gd", builtin.lsp_definitions, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "gi", builtin.lsp_implementations, opts)
    vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
    vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set("n", "<space>wl", function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)
    vim.keymap.set('n', '<space>ws', builtin.lsp_workspace_symbols, {})
    vim.keymap.set('n', '<space>ds', builtin.lsp_document_symbols, {})
    vim.keymap.set("n", "<space>D", builtin.lsp_type_definitions, opts)
    vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set({ "n", "v" }, "<space>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "gr", builtin.lsp_references, opts)
  end,
})

-- nvim-cmpのセットアップ
local cmp = require("cmp")
cmp.setup({
  sources = {
    { name = "nvim_lsp" },
    -- 他のソースをここに追加できます
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.abort(),
    ['<CR>'] = cmp.mapping.confirm({ select = true }),
  }),
})

-- LSPの機能をnvim-cmpに提供
local capabilities = cmp_nvim_lsp.default_capabilities()

-- goplsの設定
lspconfig.gopls.setup({
  capabilities = capabilities,
  cmd = {"gopls"},
  filetypes = {"go", "gomod", "gowork", "gotmpl"},
  root_dir = lspconfig.util.root_pattern("go.work", "go.mod", ".git"),
  settings = {
    gopls = {
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
    },
  },
})

vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.go",
  callback = function(args)
    -- 自動フォーマット（オプション）
    vim.lsp.buf.format()
    -- インポートの自動整理（オプション）
    vim.lsp.buf.code_action { context = { only = { 'source.organizeImports' } }, apply = true }
    vim.lsp.buf.code_action { context = { only = { 'source.fixAll' } }, apply = true }
  end,
})

-- ruby-lspの設定
lspconfig.ruby_lsp.setup({
  capabilities = capabilities,
  cmd = { "ruby-lsp" },
  filetypes = { "ruby", "eruby" },
  root_dir = lspconfig.util.root_pattern("Gemfile", ".git"),
  init_options = {
    formatter = 'auto'
  },
  single_file_support = true,
  on_attach = function(client, bufnr)
    -- 保存時に自動修正を適用する
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = bufnr,
      callback = function()
        vim.lsp.buf.format({ async = false })
      end,
    })
  end,
})
