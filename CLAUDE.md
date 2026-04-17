# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Personal macOS dotfiles. Primary content is a Neovim config (Lua + `lazy.nvim`); the rest are shell/tmux/git dotfiles and a `cheats/` directory for `navi`. There is no build system, test suite, or linter — changes are validated by running Neovim or reloading the shell.

## Install / apply changes

`setup.sh` creates symlinks; it is idempotent (uses `ln -sf`).

```bash
bash ~/dotfiles/setup.sh
```

Symlink layout created by `setup.sh`:
- `$HOME/.tmux.conf`, `.bash_aliases`, `.bash_profile`, `.bashrc`, `.gemrc`, `.gitignore_global` → repo root
- `~/.config/nvim/init.lua`, `~/.config/nvim/lazy-lock.json` → repo root
- `~/.cheats/*.cheat` → each file in `cheats/`

After editing a dotfile tracked by `setup.sh`, no re-run is needed (symlinks point to the working tree); after *adding* a new dotfile, update `DOT_FILES` in `setup.sh` and re-run it.

## Neovim architecture

- `init.lua` bootstraps `lazy.nvim`, then `require("lazy").setup({ spec = { { import = "plugins" } } })` followed by `require('config.init')`.
- `lua/plugins/*.lua` — **lazy.nvim plugin specs** (declarations of which plugins to install and their lazy-load events). Grouped by domain: `coding.lua`, `colorscheme.lua`, `treesitter.lua`, `ui.lua`, `tools.lua`. `lua/plugins/init.lua` lists the imports.
- `lua/config/*.lua` — **per-plugin configuration** (keymaps, `setup()` calls, options) applied after plugins load. `lua/config/init.lua` is the manifest that `require`s each module; adding a new `plugins_xxx.lua` here requires adding a corresponding `require('config.plugins_xxx')` line.
- `lua/config/basic.lua` — non-plugin editor setup: tab/indent/encoding/folding options, colorscheme, filetype autocmds, disabled modelines, and a `vim.secure.read`-gated `.vimrc.local` loader.
- `lazy-lock.json` — commit pins for every plugin; committed to git. Do **not** hand-edit. It is owned by Renovate in this repo; avoid running `:Lazy update` and committing the result locally, as it will conflict with open Renovate PRs.

## Plugin updates via Renovate (non-obvious)

Plugin updates in this repo do **not** come from `:Lazy update` → commit. They come from Renovate PRs that bump individual commit SHAs in `lazy-lock.json`.

- `renovate.json` extends `local>takaneko/dotfiles:renovate-lazy` → the presets live in `renovate-lazy.json`.
- `renovate-lazy.json` contains one `customManagers` entry per plugin, each a regex that targets `"<plugin>": { "branch": "...", "commit": "..." }` in `lazy-lock.json`. Without an entry, a plugin is invisible to Renovate.
- **After adding, renaming, or removing a plugin in `lua/plugins/*.lua`, regenerate `renovate-lazy.json`:**

  ```bash
  nvim --headless -c "luafile ~/dotfiles/scripts/gen-renovate-managers.lua" -c "qa"
  ```

  The generator reads the live `require("lazy").plugins()` result, so it requires `~/dotfiles/init.lua` to be the active Neovim config (i.e. `setup.sh` has been run) and all plugins installed.

- `.github/workflows/renovate.yml` runs the Renovate action on a weekly cron. `minimumReleaseAge: "10 days"` is set globally (except for security alerts).

## Reviewing Renovate PRs

The `/review-renovate-pr` skill (defined in `.claude/skills/review-renovate-pr/SKILL.md`) handles triage of open Renovate PRs: it enforces the 10-day age gate, scans upstream diffs for supply-chain red flags, and posts a review comment per PR. Use it instead of reviewing Renovate PRs by hand. It must be run from `~/dotfiles` because it reads `renovate-lazy.json` via a relative path.
