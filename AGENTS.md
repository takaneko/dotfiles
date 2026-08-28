# dotfiles

This file is the agent-neutral entry point for this repository; `CLAUDE.md` is a symlink to it, so Claude Code reads the same content.

## Repository purpose

Personal macOS dotfiles. Primary content is a Neovim config (Lua + `lazy.nvim`); the rest are shell/tmux/git dotfiles and a `cheats/` directory for `navi`. There is no build system, test suite, or linter — changes are validated by running Neovim or reloading the shell.

## Agent config layout (`.agents/` and `.claude/`)

Agent-neutral assets live in **`.agents/` as the real files, with `.claude/` pointing at them through relative symlinks**. Other agents get the same copies, while everything that hardcodes a `.claude/` path keeps resolving.

```
.agents/skills/  ← real    .claude/skills -> ../.agents/skills
.agents/plans/   ← real    .claude/plans  -> ../.agents/plans

.claude/settings.local.json, .claude/.gitignore, .claude/skill-retros/  ← real, stay put
AGENTS.md        ← real    CLAUDE.md      -> AGENTS.md
```

This repo has no `.claude/rules/`; the table below is the general classification, so it lists items this repo does not have.

### Classification

| Class | Handling | Items | Why |
|---|---|---|---|
| **Shareable** | real file in `.agents/`, symlink from `.claude/` | `rules/`, `plans/`, `skills/` | agent-neutral assets other agents should reach too |
| **Claude Code specific** | stays in `.claude/` | `settings.json`, `settings.local.json`, `scheduled_tasks.lock`, `.gitignore` | only Claude Code reads them; `.claude/.gitignore` scopes an exclusion to that directory |
| **Skill output** | leave alone | `project-health-report.md`, `skill-retros/`, `retro/`, `blog-ideas/` | artifacts a skill writes; don't move them unless the producing skill's output path moves |
| **Unclear** | **stays in `.claude/`** | — | don't move what you haven't classified |

### Does a symlink actually work?

Measured 2026-08-28 (macOS 25.6.0, Claude Code 2.1.250).

**Skill discovery works through a directory symlink — this is the one that matters.** Everything else here is about reaching file *contents*; discovery is whether the runtime enumerates `.claude/skills/` at all. A skill that is not discovered simply stops existing as a `/`-command, with no error. Verified directly rather than assumed:

```bash
cd ~/dotfiles
claude -p "Without using any tools, list the names of the project-level skills available to you that start with 'review-'. If there are none, reply exactly: NONE"
# → review-brew-outdated, review-renovate-pr
```

The only copies on disk are under `.agents/`, so the runtime followed the link. `claude -p` needs no interactive session, so the same check works in any repo — but **swap the `review-` prefix for whatever that repo's skills are actually called.** Left as-is it answers `NONE` in a repo whose skills are named otherwise, and that false negative reads exactly like a discovery failure. **Check contents AND discovery — passing the first proves nothing about the second.**

**Recursive tools do not follow symlinks by default.**

| Tool | link met while walking | link passed as an argument |
|---|---|---|
| `find` | does not follow (`-L` needed) | does not follow — **but a trailing `/` makes it follow** |
| `rg` | does not follow (`--follow` needed) | **follows** |
| shell glob (`ls .claude/skills/*/SKILL.md`) | follows | follows |
| Claude Code Read tool | — | **follows** |
| Claude Code Glob / Grep tools | **check per environment** | **check per environment** |

The `find` trailing-slash asymmetry is the easy one to trip on, confirmed live in this repo: `find .claude/skills -name '*.md'` returns 0, `find .claude/skills/ -name '*.md'` returns 2. Nothing here depends on it today (checked `setup.sh`, `scripts/`, both `SKILL.md`, this file), but it is the only traversal that silently returns nothing. **So when a skill or script looks for files through a link, use a shell glob or pass the link as an argument — don't rely on pattern-based recursion.**

The Glob / Grep row says "check per environment" because it depends on the build: this one has no such tools (`ToolSearch select:Glob,Grep` returns nothing), so file lookup goes through `rg` / `find` and their rows are what actually apply.

**Executable bits survive.** `adapters/*.sh` are mode `100755`; through the link they still read `-rwxr-xr-x` and both `bash …` and `test -x` pass.

**git records a directory symlink as a mode `120000` blob** whose content is the relative path itself. Same relative path ⇒ same blob, so expected values can be fixed up front:

| Link | blob |
|---|---|
| `.claude/skills -> ../.agents/skills` | `2b7a412` |
| `.claude/plans -> ../.agents/plans` | `3b851bb` |
| `.claude/rules -> ../.agents/rules` | `2d5c9a9` (unused here; for rollout) |

`git mv` preserves both history and the exec bits. Note that converting `CLAUDE.md` into a symlink is **not** recorded as a rename — the path is not deleted, just retyped — so `git status` shows `A AGENTS.md` + `T CLAUDE.md` and `-M` finds nothing. Verify that one by diffing against `HEAD:CLAUDE.md`.

### gitignore: the sharp edge

**`~/.gitignore_global` is a file in this repo** (`~/.gitignore_global` → `~/dotfiles/.gitignore_global`), so its `.claude/`-pinned lines are editable from here. Two of them name paths directly:

- `.gitignore_global:52` — `.claude/settings.local.json`
- `.gitignore_global:58` — `.claude/skill-retros`

Plus, repo-local: `.gitignore:2` is `/.claude/skill-retros/` (**leading `/` anchors it**, so it stops matching entirely if the directory moves), and `.claude/.gitignore:1` is `settings.local.json`, which works by sitting in that directory.

All of these cover items classified as staying in `.claude/`, so they are unaffected — **and that is exactly why none of them may move.** Moving one silently un-ignores a local settings file.

**`.agents/` has no exclusions at all.** Everything under it is tracked, which is right for the assets moved so far. But if you later put local settings or skill output under `.agents/`, decide whether it needs an exclusion *before* adding it.

Line numbers drift; re-derive them per machine:

```bash
grep -n '\.claude/' ~/dotfiles/.gitignore_global
```

### Rolling this out to another repo

1. Classify first; move only what the table calls shareable, one item at a time — never the whole directory.
2. `git mv` the real files into `.agents/`, then **`rmdir` the old directory before `ln -s`**. `git mv` only moves tracked files, so a stray untracked file leaves the directory in place and the link lands *inside* it (`.claude/skills/skills`). **`git add` the new link afterwards** — otherwise it stays untracked while git records the old path as deleted, which commits a half-migration.
3. For a `plans/` that does not exist yet, create it with a `.gitkeep` so git tracks the empty directory. Move any existing plan file out *before* linking — the plan describing this work lived in the directory being converted.
4. Repoint every path that names something you moved. Two separate cases, and it is easy to fix only the first: a skill that documents **its own** directory, and the entry doc's prose references to the moved assets (here, the two sentences naming where each skill is defined).
5. Make `AGENTS.md` the real file and `CLAUDE.md` the symlink; fix the heading and the opening line, which otherwise still name Claude Code on what is now the neutral entry point.
6. **Verify discovery with the `claude -p` one-liner above**, and confirm `git check-ignore -v .claude/settings.local.json` still resolves.

Two other personal repos still need this applied.

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

The `/review-renovate-pr` skill (defined in `.agents/skills/review-renovate-pr/SKILL.md`) handles triage of open Renovate PRs of three kinds — `lazy-lock.json` plugin digest bumps, `aqua.yaml` CLI tool tag bumps, and the `aquaproj/aqua-registry` `registries[].ref` bump. It enforces the 10-day age gate, scans for supply-chain red flags — the commit range for lazy, the old→new tag for aqua, and for a registry bump a git-**trees** blob-SHA comparison of only our installed packages' `pkgs/<pkg>/pkg.yaml` **and** `pkgs/<pkg>/registry.yaml` (the compare API truncates at 300 files, so it's the wrong tool there) looking for download URL/host/asset/verification changes — flags aqua/registry PRs that lack the regenerated `aqua-checksums.json`, and posts a review comment per PR. Both registry files must be compared: `pkg.yaml` holds only the version alias, so `registry.yaml` is the one that actually carries the download metadata a redirect would alter. Preset/action bumps (`aqua-renovate-config` in `renovate.json5`, `.github/workflows/*`) remain out of scope and skipped. Use it instead of reviewing Renovate PRs by hand. It must be run from `~/dotfiles` because it reads `renovate-lazy.json` via a relative path.

## Reviewing Homebrew updates

Homebrew is not under Renovate's control (the `brew` manager is intentionally not enabled), so `brew outdated` accumulates between manual triages. The `/review-brew-outdated` skill (defined in `.agents/skills/review-brew-outdated/SKILL.md`) runs a CVE scan (`syft /opt/homebrew/Cellar | grype`) against installed formulae, enforces the same 10-day age gate, analyzes upstream GitHub diffs, and prints a paste-able `brew upgrade` command covering only the approved formulae. The skill never runs `brew upgrade` itself. Requires `syft` and `grype` (both installed via `aqua.yaml`).
