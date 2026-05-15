-- nvim-treesitter main branch 用設定。
-- master 系の configs.setup{} は廃止。パーサーは install() で、機能は
-- vim.treesitter.start() + foldexpr / indentexpr の組み合わせで個別に有効化する。

-- gowork は upstream の omertuc/tree-sitter-go-work が default branch を
-- master→main にリネームしており、archive 済み nvim-treesitter の install
-- ロジック(rename先を `<repo>-master` に hardcode)と噛み合わずインストール
-- 不能。go.work ファイル編集時に困ったら再考。
local ensure_installed = {
  "typescript", "tsx",
  "go", "gomod",
  "graphql",
  "ruby", "rbs",
  "dart",
  "terraform",
  "lua", "vim", "vimdoc", "query",
  "html", "css", "json", "yaml", "toml",
  "markdown", "markdown_inline",
}

require("nvim-treesitter").install(ensure_installed)

-- mdx を markdown として扱う
vim.treesitter.language.register("markdown", "mdx")

-- Ruby は treesitter の indent / highlight が成熟しておらず、過去から
-- regex highlight 併用 + indent 無効を維持している。regex hl は :syntax on
-- (basic.lua) が既に enable してるので、ここでは indent だけ無効化する。
local ruby_quirks = function(buf)
  vim.bo[buf].indentexpr = ""
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
    if not lang or lang == "" then
      return
    end
    if not pcall(vim.treesitter.start, ev.buf, lang) then
      return
    end
    if lang == "ruby" then
      ruby_quirks(ev.buf)
    else
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
    vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
    vim.wo[0][0].foldmethod = "expr"
  end,
})

-- 旧 nvim-treesitter master の incremental_selection 代替（main では削除）。
-- gnn: カーソル位置の最小ノードを選択、grn: 親ノードに拡張、grc: スコープに拡張、
-- grm: 直前の拡張を取り消す（履歴 pop）。
local sel_stack = {}
local function push_and_select(node)
  if not node then
    return
  end
  sel_stack[#sel_stack + 1] = node
  local sr, sc, er, ec = node:range()
  vim.fn.setpos("'<", { 0, sr + 1, sc + 1, 0 })
  vim.fn.setpos("'>", { 0, er + 1, ec, 0 })
  vim.cmd("normal! gv")
end

vim.keymap.set("n", "gnn", function()
  sel_stack = {}
  push_and_select(vim.treesitter.get_node())
end, { desc = "TS: init node selection" })

vim.keymap.set("x", "grn", function()
  local cur = sel_stack[#sel_stack]
  if cur and cur:parent() then
    push_and_select(cur:parent())
  end
end, { desc = "TS: expand to parent node" })

vim.keymap.set("x", "grc", function()
  local node = sel_stack[#sel_stack]
  while node and node:parent() do
    node = node:parent()
    local t = node:type()
    if t:match("block$") or t:match("body$") or t:match("function") or t:match("method") then
      push_and_select(node)
      return
    end
  end
end, { desc = "TS: expand to enclosing scope" })

vim.keymap.set("x", "grm", function()
  if #sel_stack > 1 then
    table.remove(sel_stack)
    local prev = sel_stack[#sel_stack]
    local sr, sc, er, ec = prev:range()
    vim.fn.setpos("'<", { 0, sr + 1, sc + 1, 0 })
    vim.fn.setpos("'>", { 0, er + 1, ec, 0 })
    vim.cmd("normal! gv")
  end
end, { desc = "TS: shrink to previous selection" })
