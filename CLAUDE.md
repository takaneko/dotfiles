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

## aqua bootstrap

`scripts/bootstrap-aqua.sh` is a standalone installer for **aqua** — it is NOT invoked from `setup.sh`. Run it manually on a fresh machine, or re-run after bumping `AQUA_VERSION` in the script. It downloads the official aqua tarball, verifies the pinned SHA256, generates `aqua-checksums.json` on first run (TOFU), then runs `aqua install -a` against `aqua.yaml`.

```bash
bash ~/dotfiles/scripts/bootstrap-aqua.sh
```

## CLI tooling via aqua

Most CLI tools (gh, jq, helm, kubectl, ripgrep, fd, direnv, navi, neovim, …) are installed by **aqua** rather than Homebrew, with version + SHA256 pinning for supply-chain hardening.

- `aqua.yaml` — single source of truth for installed tools. Lists the aqua-registry ref, packages with pinned tags, and `checksum: { enabled: true, require_checksum: true, supported_envs: [darwin/arm64] }`.
- `aqua-checksums.json` — SHA256 of every fetched asset. Auto-generated on first run by `scripts/bootstrap-aqua.sh` (Trust on First Use), then committed. Once committed, any drift in upstream binary content makes install fail.
- `AQUA_GLOBAL_CONFIG=$HOME/dotfiles/aqua.yaml` is exported in `.bashrc`, so `aqua` commands work from any cwd.
- aqua's `bin` directory is prepended to PATH **before** the `direnv hook` / `navi widget` evals so those evals resolve to the aqua-managed binaries, not the brew-managed ones.

Homebrew is intentionally retained only for things aqua can't manage: macOS GUI casks, shared libraries, build tools, language runtimes (`python@3.10`, `perl`, `lua`, …), GNU userland (`gnu-sed`, `gnu-getopt`, `coreutils`), and daemons (`mysql`, `postgresql@15`, `redis`).

### Adding / removing a package

1. Edit `aqua.yaml` (add or remove a `- name: owner/repo@vX.Y.Z` entry).
2. Run `aqua update-checksum -a` to refresh `aqua-checksums.json` so the new asset's SHA is recorded.
3. Run `aqua install -a` to apply.
4. Commit both `aqua.yaml` and `aqua-checksums.json` in the same commit.

Step 2 is **mandatory for manual edits**: CI only regenerates `aqua-checksums.json` automatically for Renovate-authored PRs (via the `postUpgradeTasks` `aqua upc` hook — see below). A human PR that edits `aqua.yaml` without running `aqua update-checksum -a` will merge with a missing SHA and fail the next `aqua install` (`require_checksum: true`).

### aqua updates via Renovate

`renovate.json5` extends `github>aquaproj/aqua-renovate-config#2.9.0`, which configures:
- The built-in `aqua` manager: opens a per-package PR when a new tag is released for any entry in `aqua.yaml`.
- Updates for the `registries: ref:` (aqua-registry version).
- Updates for `aqua-installer` and the `aquaproj/aqua-renovate-config` preset itself.

`aqua-renovate-config` can't update `aqua-checksums.json`, so `renovate.json5` adds a `postUpgradeTasks` hook that runs `aqua upc -a --prune` on any branch touching `aqua.yaml`, committing the regenerated checksums into the same Renovate PR. This is why `.github/workflows/renovate.yml` runs Renovate via `npx` (not the container action) with `aqua` on `PATH`, and allow-lists exactly that one command via `RENOVATE_ALLOWED_COMMANDS`. It covers **Renovate PRs only** — manual `aqua.yaml` edits still need step 2 above. (There is intentionally no `on: pull_request` checksum workflow: it can't auto-run on bot-authored PRs because GitHub gates `github-actions[bot]` PR workflows as `action_required`.)

`minimumReleaseAge: "10 days"` (set globally) applies to aqua PRs as well, matching the lazy-lock.json policy. The `/review-renovate-pr` skill covers `aqua.yaml` tag PRs in the same style as the lazy plugin reviews (age gate + upstream-diff red-flag scan against the old→new tag, plus a check that the PR carries the regenerated `aqua-checksums.json`).

### Bumping aqua itself

`AQUA_VERSION` and the darwin-arm64 SHA256 are pinned at the top of `scripts/bootstrap-aqua.sh`. To upgrade:
1. Pick the target tag from <https://github.com/aquaproj/aqua/releases>.
2. Download `aqua_<tag>_checksums.txt` and (ideally) verify its Cosign signature once.
3. Update `AQUA_VERSION` and `AQUA_DARWIN_ARM64_SHA256` in `scripts/bootstrap-aqua.sh`.
4. Re-run `bash ~/dotfiles/scripts/bootstrap-aqua.sh` to verify bootstrap succeeds.

## Neovim architecture

- `init.lua` bootstraps `lazy.nvim`, then `require("lazy").setup({ spec = { { import = "plugins" } } })` followed by `require('config.init')`.
- `lua/plugins/*.lua` — **lazy.nvim plugin specs** (declarations of which plugins to install and their lazy-load events). Grouped by domain: `coding.lua`, `colorscheme.lua`, `treesitter.lua`, `ui.lua`, `tools.lua`. `lua/plugins/init.lua` lists the imports.
- `lua/config/*.lua` — **per-plugin configuration** (keymaps, `setup()` calls, options) applied after plugins load. `lua/config/init.lua` is the manifest that `require`s each module; adding a new `plugins_xxx.lua` here requires adding a corresponding `require('config.plugins_xxx')` line.
- `lua/config/basic.lua` — non-plugin editor setup: tab/indent/encoding/folding options, colorscheme, filetype autocmds, disabled modelines, and a `vim.secure.read`-gated `.vimrc.local` loader.
- `lazy-lock.json` — commit pins for every plugin; committed to git. Do **not** hand-edit. It is owned by Renovate in this repo; avoid running `:Lazy update` and committing the result locally, as it will conflict with open Renovate PRs.

### Lazy commands: what to use and what to avoid

Renovate-managed lock file means **bulk lazy commands are off-limits**. They drift every plugin past its Renovate pin in one shot.

- ❌ `:Lazy sync` — install + update + clean. Bumps every plugin to tip. Never run unscoped.
- ❌ `:Lazy update` (no args) — bumps every plugin.
- ✅ Just restarting `nvim` — lazy auto-installs missing plugins on startup, touching only their new lock entries.
- ✅ `:Lazy install <name>` — install one missing plugin and add its lock entry.
- ✅ `:Lazy update <name>` — update one plugin to tip (use only when you genuinely need to bump it outside Renovate; e.g. to record a branch switch in the lock).
- ✅ `:Lazy clean` — remove orphan plugins (installed but no longer in spec). Drops their lock entries too.

If a bulk command got run accidentally and the lock drifted, the recovery is `git checkout HEAD -- lazy-lock.json` followed by the scoped commands above to re-record only the intended deltas.

## nvim-treesitter is on the archived `main` branch

The upstream `nvim-treesitter/nvim-treesitter` repository was archived in April 2026. We pin to the `main` branch (the v1.0 rewrite, nvim 0.12+ only) rather than `master` (nvim ≤0.11). Implications:

- `lua/plugins/treesitter.lua` sets `branch = "main"` and `lazy = false` — **main does not support lazy-loading** (see upstream README). Do not add `event = ...` / `cmd = ...` / etc. to the spec.
- The `configs.setup{}` form is gone. `lua/config/plugins_treesitter.lua` uses the new API: `require('nvim-treesitter').install({...})` to declare parsers, plus a `FileType` autocmd that calls `vim.treesitter.start()` and sets `foldexpr` / `indentexpr` per buffer.
- The `tree-sitter` CLI is required: some parsers (e.g. `terraform`, which lives in a `dialects/` subdir of `tree-sitter-hcl`) lack a pre-generated `parser.c` and have nvim-treesitter invoke `tree-sitter build` at install time. The CLI is pinned in `aqua.yaml` as `tree-sitter/tree-sitter`.
- The repo being archived means no future fixes. Renovate will stop receiving updates for `nvim-treesitter` once `main` stops moving; this is acceptable as long as nvim 0.12 remains the active line. Reassess if nvim 0.13 breaks the treesitter API.
- `nvim-treesitter-context` is kept because it talks to `vim.treesitter` directly and does not depend on nvim-treesitter's `configs` API. It also ships its own per-language context queries.
- `windwp/nvim-ts-autotag` replaces the old in-tree `autotag` module (removed in main) for TSX/JSX/HTML tag auto-close.
- The incremental-selection feature (gnn/grn/grc/grm) was likewise removed; `lua/config/plugins_treesitter.lua` hand-rolls equivalent keymaps on top of `vim.treesitter.get_node()`.

## Plugin updates via Renovate (non-obvious)

Plugin updates in this repo do **not** come from `:Lazy update` → commit. They come from Renovate PRs that bump individual commit SHAs in `lazy-lock.json`.

- `renovate.json5` extends `local>takaneko/dotfiles:renovate-lazy` → the presets live in `renovate-lazy.json`. JSON5 is used for the top-level config so that rules (e.g. the navi disable) can carry inline comments explaining rationale.
- `renovate-lazy.json` contains one `customManagers` entry per plugin, each a regex that targets `"<plugin>": { "branch": "...", "commit": "..." }` in `lazy-lock.json`. Without an entry, a plugin is invisible to Renovate.
- **After adding, renaming, or removing a plugin in `lua/plugins/*.lua`, regenerate `renovate-lazy.json`:**

  ```bash
  nvim --headless -c "luafile ~/dotfiles/scripts/gen-renovate-managers.lua" -c "qa"
  ```

  The generator reads the live `require("lazy").plugins()` result, so it requires `~/dotfiles/init.lua` to be the active Neovim config (i.e. `setup.sh` has been run) and all plugins installed.

- `.github/workflows/renovate.yml` runs the Renovate action on a weekly cron. `minimumReleaseAge: "10 days"` is set globally (except for security alerts).

## Reviewing Renovate PRs

The `/review-renovate-pr` skill (defined in `.claude/skills/review-renovate-pr/SKILL.md`) handles triage of open Renovate PRs of three kinds — `lazy-lock.json` plugin digest bumps, `aqua.yaml` CLI tool tag bumps, and the `aquaproj/aqua-registry` `registries[].ref` bump. It enforces the 10-day age gate, scans for supply-chain red flags — the commit range for lazy, the old→new tag for aqua, and for a registry bump a git-**trees** blob-SHA comparison of only our installed packages' `pkgs/<pkg>/pkg.yaml` (the compare API truncates at 300 files, so it's the wrong tool there) looking for download URL/host/asset/verification changes — flags aqua/registry PRs that lack the regenerated `aqua-checksums.json`, and posts a review comment per PR. Preset/action bumps (`aqua-renovate-config` in `renovate.json5`, `.github/workflows/*`) remain out of scope and skipped. Use it instead of reviewing Renovate PRs by hand. It must be run from `~/dotfiles` because it reads `renovate-lazy.json` via a relative path.

## Reviewing Homebrew updates

Homebrew is not under Renovate's control (the `brew` manager is intentionally not enabled), so `brew outdated` accumulates between manual triages. The `/review-brew-outdated` skill (defined in `.claude/skills/review-brew-outdated/SKILL.md`) runs a CVE scan (`syft /opt/homebrew/Cellar | grype`) against installed formulae, enforces the same 10-day age gate, analyzes upstream GitHub diffs, and prints a paste-able `brew upgrade` command covering only the approved formulae. The skill never runs `brew upgrade` itself. Requires `syft` and `grype` (both installed via `aqua.yaml`).
