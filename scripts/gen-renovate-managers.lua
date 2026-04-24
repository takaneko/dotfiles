-- Regenerate renovate-lazy.json (a Renovate local preset) from the lazy.nvim
-- plugin spec. renovate.json extends this file via `local>...`, so hand-edits
-- to renovate.json are preserved.
-- Run from anywhere:
--   nvim --headless -c "luafile ~/dotfiles/scripts/gen-renovate-managers.lua" -c "qa"

-- Resolve the dotfiles root from this script's own location so the output
-- path doesn't depend on the caller's cwd.
local this = debug.getinfo(1, "S").source:sub(2)
local root = this:match("(.+)/scripts/[^/]+$")
assert(root, "could not resolve dotfiles root from " .. this)

-- Escape JS regex special chars so plugin names with unusual punctuation
-- still yield a valid matchStrings pattern.
local function regex_escape(s)
  return (s:gsub("([%.%+%*%?%(%)%[%]%{%}%|%^%$])", [[\\%1]]))
end

local plugins = require("lazy").plugins()
table.sort(plugins, function(a, b) return a.name < b.name end)

local entries = {}
for _, p in ipairs(plugins) do
  if p.url and p.name then
    local url = p.url:gsub("%.git$", "")
    if p.tag then
      -- Tag-pinned plugin: Renovate should track GitHub tags by editing the
      -- plugin spec file's `tag = '...'` line, not lazy-lock.json (which lazy
      -- regenerates from the tag). Exclude this plugin from the lock-file
      -- regex manager to avoid dual management / master-branch chasing.
      local pkg = url:gsub("^https://github%.com/", "")
      local pkg_escaped = regex_escape(pkg)
      entries[#entries + 1] = string.format(
        [[    {
      "customType": "regex",
      "managerFilePatterns": ["lua/plugins/**/*.lua"],
      "matchStrings": ["'%s',\\s+tag\\s*=\\s*'(?<currentValue>[^']+)'"],
      "depNameTemplate": "%s",
      "packageNameTemplate": "%s",
      "datasourceTemplate": "github-tags",
      "versioningTemplate": "semver-coerced"
    }]],
        pkg_escaped, p.name, pkg
      )
    else
      local key = regex_escape(p.name)
      entries[#entries + 1] = string.format(
        [[    {
      "customType": "regex",
      "managerFilePatterns": ["**/lazy-lock.json"],
      "matchStrings": ["\"%s\":\\s*\\{\\s*\"branch\":\\s*\"(?<currentValue>[^\"]+)\",\\s*\"commit\":\\s*\"(?<currentDigest>[a-f0-9]+)\"\\s*\\}"],
      "depNameTemplate": "%s",
      "packageNameTemplate": "%s",
      "datasourceTemplate": "git-refs"
    }]],
        key, p.name, url
      )
    end
  end
end

local output = string.format([[{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "customManagers": [
%s
  ]
}
]], table.concat(entries, ",\n"))

local out = root .. "/renovate-lazy.json"
local f = assert(io.open(out, "w"))
f:write(output)
f:close()
print(string.format("Regenerated %s with %d customManagers", out, #entries))
