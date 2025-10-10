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
vim.lsp.config('gopls', {
  capabilities = capabilities,
  settings = {
    gopls = {
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
    },
  },
  on_attach = function(client, bufnr)
    -- 保存時に自動修正を適用する
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = bufnr,
      callback = function()
        -- 自動フォーマット（オプション）
        vim.lsp.buf.format()
        -- インポートの自動整理（オプション）
        vim.lsp.buf.code_action { context = { only = { 'source.organizeImports' }, diagnostics = {} }, apply = true }
        vim.lsp.buf.code_action { context = { only = { 'source.fixAll' }, diagnostics = {} }, apply = true }
      end,
    })
  end,
})
vim.lsp.enable('gopls')

-- ruby-lspの設定
vim.lsp.config('ruby_lsp', {
  capabilities = capabilities,
  filetypes = { 'ruby' },
  init_options = {
    formatter = 'auto'
  },
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
vim.lsp.enable('ruby_lsp')

-- tsserverの設定
vim.lsp.config('ts_ls', {
  capabilities = capabilities,
  filetypes =  {'typescript', 'typescriptreact', 'javascript', 'javascriptreact'},
  root_makers = {'.git', 'package.json', 'tsconfig.json'}
})
vim.lsp.enable('ts_ls')

-- tailwindcssの設定
vim.lsp.config('tailwindcss', {
  capabilities = capabilities,
  settings = {
    tailwindCSS = {
      emmetCompletions = true,
    },
  },
})
vim.lsp.enable('tailwindcss')

-- astroの設定
vim.lsp.config('astro', {
  capabilities = capabilities,
})
vim.lsp.enable('astro')

-- mdxの設定
vim.lsp.config('mdx_analyzer', {
  capabilities = capabilities,
})
vim.lsp.enable('mdx_analyzer')

-- luaの設定
vim.lsp.config('lua_ls', {
  settings = {
    Lua = {
      runtime = {
        version = 'LuaJIT',
      },
      diagnostics = {
        globals = {'vim'},
      },
      workspace = {
        library = vim.api.nvim_get_runtime_file("", true),
        checkThirdParty = false,
      },
      telemetry = {
        enable = false,
      },
    },
  },
})
vim.lsp.enable('lua_ls')
