---
name: review-brew-outdated
description: Review Homebrew formulae reported by `brew outdated`, classify each update by security impact and release age, analyze the upstream diff for supply-chain red flags, and print a chat summary with a ready-to-paste `brew upgrade` command covering only the approved packages. Triggered by requests like "review brew outdated", "triage homebrew updates", "check if brew packages are safe to upgrade", or explicit /review-brew-outdated invocation.
---

# review-brew-outdated

Reviews outdated Homebrew formulae and decides which are safe to upgrade. For each candidate it:

1. Cross-references installed versions against a CVE scan (syft + grype) to flag security-relevant updates.
2. Enforces a 10-day release-age gate for non-security updates (same policy as Renovate).
3. Scans the upstream diff for supply-chain red flags (remote script exec, credential access, obfuscation, unexpected dependency pulls). Host-aware: GitHub, GitLab, Bitbucket Cloud, and generic git (cgit / self-hosted) are all supported via per-kind adapters.
4. Prints a chat summary and a `brew upgrade` command covering only packages classified as UPDATE.

The skill never runs `brew upgrade` itself — the user runs the printed command.

## Scope

- Formulae only. Casks are listed as "manual review" in the summary but not analyzed.
- Optional package arguments: `/review-brew-outdated jq git` restricts processing to the named formulae. No arguments processes every outdated formula.
- Safe to re-run — per-run artefacts under `/tmp/brew-*.{json,patch}` are overwritten each time. The `git` adapter's bare-clone cache at `/tmp/brew-review-cache/` persists across invocations for speed (re-runs just `git fetch` instead of re-cloning) and is safe to delete between runs.

## Required tools

`brew`, `gh` (authed), `jq`, `syft`, `grype`, `curl`, `git`. All are installed via aqua (`anchore/syft`, `anchore/grype`) or available by default on the system.

## Steps

### 1. Collect the outdated list

```bash
brew outdated --json=v2 --formula > /tmp/brew-outdated.json
jq '.formulae | length' /tmp/brew-outdated.json
```

Each entry has `name`, `installed_versions` (array), `current_version` (which despite the name is the **latest available** version). Filter by CLI arguments if any were passed; otherwise take all.

Also capture casks for the final summary:

```bash
brew outdated --json=v2 --cask | jq '.casks | map(.name)' > /tmp/brew-outdated-casks.json
```

If the formula list is empty, tell the user "No outdated formulae." and (if any casks) list the cask names as "manual review". Stop.

### 2. Scan installed packages for known CVEs

This is the most expensive step — run it once, before per-package work. The SBOM covers the entire Cellar so it does not need to be re-generated per formula.

```bash
HOMEBREW_CELLAR="$(brew --cellar)"
syft "$HOMEBREW_CELLAR" -o cyclonedx-json > /tmp/brew-sbom.json 2>/dev/null
grype sbom:/tmp/brew-sbom.json -o json > /tmp/brew-cves.json 2>/dev/null
```

Build a map from formula name → list of CVE matches (brew packages only — syft also catalogs vendored deps like python wheels inside bottles, which we do not care about because `brew upgrade` cannot act on them):

```bash
jq '[.matches[]
  | select(.artifact.purl | startswith("pkg:brew/"))
  | {name: .artifact.name, version: .artifact.version,
     cve: .vulnerability.id, severity: .vulnerability.severity,
     fix: (.vulnerability.fix.versions // [])}]
  | group_by(.name)
  | map({(.[0].name): .})
  | add // {}' /tmp/brew-cves.json > /tmp/brew-cve-by-name.json
```

The trailing `// {}` matters: when grype finds zero brew matches, `add` returns `null`, and downstream `has()` / `keys` calls against `null` would abort the run.

Any formula present as a key here is a **SECURITY** candidate — grype has matched it against at least one known advisory. The `fix` array being empty does not disqualify the formula, because upstream databases routinely lag new releases; a grype hit on an outdated package is strong signal that the pending upgrade matters for security.

### 3. Resolve each formula's upstream

```bash
brew info --json=v2 <name> | jq '.formulae[0] | {homepage, stable_url: .urls.stable.url, head_url: .urls.head.url}'
```

Classify the upstream into one of four **kinds** and record `{kind, key}` per formula. Check `head_url` first, then `stable_url`, then `homepage`. Match against each pattern in order; the first kind that matches wins:

| Kind | URL pattern | Key (args passed to adapter) |
|---|---|---|
| `github` | `https?://github\.com/<owner>/<repo>` | `<owner>/<repo>` |
| `gitlab` | `https?://<host>/<project_path>` where `<host>` starts with `gitlab.` or is in the known-GitLab list (`code.videolan.org`, `salsa.debian.org`, `foss.heptapod.net`) | `<host> <project_path>` — `project_path` is the slash-joined namespace and repo; adapters URL-encode it |
| `bitbucket` | `https?://bitbucket\.org/<workspace>/<repo>` | `<workspace> <repo_slug>` — strip trailing `.git`, `/src/...`, `/downloads/...` |
| `git` | URL ends in `.git` on any other host, **or** homepage is `https://www.gnu.org/software/<name>/` (fallback: probe `https://git.savannah.gnu.org/git/<name>.git` with `git ls-remote --exit-code`; some GNU projects live on `git.gnunet.org` instead) | `<name> <clone_url>` — `<name>` is the formula name, used as the cache key |

If none match, record as **MANUAL** with reason "upstream not resolvable" and skip steps 4–6.

**Brew-revision-only bumps** (`8.1` → `8.1_1`, `1.86.0` → `1.86.0_1`): the upstream version is unchanged — only the Homebrew formula revision number bumped. Both versions resolve to the same upstream tag and `compare` returns an empty diff. Record these as UPDATE with reason "brew revision only, no upstream diff" and skip the heuristic scan. Do NOT classify as MANUAL. A revision bump commonly means a rebuild against a newer dependency; if the revision bump log message cites another formula (e.g. "revision bump for x265 4.2"), note the dependency in the summary so the user can review it separately.

**For the `git` kind only**, run the init step once per formula before resolve-tag or fetch-diff. This clones the bare repo into `${XDG_CACHE_HOME:-$HOME/.cache}/brew-review/<name>.git/` (reused on subsequent runs, with stale/invalid caches auto-removed before re-cloning):

```bash
bash "$SKILL_DIR/adapters/git.sh" init <name> <CLONE_URL>
```

Throughout the rest of this doc, `$SKILL_DIR` is this skill's directory: `$HOME/dotfiles/.claude/skills/review-brew-outdated`. Adapters live under `$SKILL_DIR/adapters/<kind>.sh` and share a uniform calling convention — see steps 4 and 6.

### 4. Resolve tag names and release date

Every adapter exposes the same `resolve-tag` verb with uniform JSON output:

```bash
bash "$SKILL_DIR/adapters/<kind>.sh" resolve-tag <key...> "<VERSION>"
# → {"name": "v1.2.3", "sha": "...", "date": "2026-04-15T..."}
# → {} if no tag contains the version string
```

Adapters apply a `contains("<VERSION>")` match against upstream tag listings — tag naming is not standardised (Homebrew's `1.6.58` may appear as `v1.6.58`, `libpng-1.6.58`, `release-1.6.58`, etc.), so substring match is the lowest-common-denominator that works across all hosts.

Call once for the installed version (`installed_versions[0]` — pin explicitly; the array normally has one entry but `brew` allows multiple installed versions for versioned formulae like `python@3.10`) and once for the latest version. If either resolves to `{}`, record the formula as **MANUAL** with reason "tag '<version>' not found" and skip step 6.

Compute age in days from the `date` field via the same portable `jq fromdate` expression (avoids BSD/GNU `date` divergence):

```bash
jq -n --arg d "<date from resolve-tag>" '($d | fromdate) as $t | ((now - $t) / 86400) | floor'
```

### 5. Classify

Apply rules in order:

| Condition | Classification | Rationale |
|---|---|---|
| Name appears in grype CVE map | **SECURITY** | Known vuln — age gate does not apply, upgrade is worth the tail risk. |
| Latest tag age ≥ 10 days | **UPDATE** (diff-pending) | Passes age gate, proceed to diff review. |
| Latest tag age < 10 days | **WAIT** | Release is too fresh — let it bake. No diff review. |
| Upstream or tag not resolvable | **MANUAL** | Cannot inspect — user decides. |

For **SECURITY** and age-PASS **UPDATE**, run step 6. **WAIT** and **MANUAL** skip diff review.

### 6. Diff review (SECURITY and UPDATE only)

Every adapter exposes the same `fetch-diff` verb, which writes two files sharing a common prefix:

```bash
OUT=/tmp/brew-diff-<name>
bash "$SKILL_DIR/adapters/<kind>.sh" fetch-diff <key...> "<OLD_REF>" "<NEW_REF>" "$OUT"
# writes $OUT.patch         — raw unified diff text (input to HIGH heuristic grep)
# writes $OUT-meta.json     — {commits, files} (input to MEDIUM heuristics)
```

Adapter exit codes:

| Exit | Meaning | Action |
|---|---|---|
| `0` | Success, both files written | Run heuristic scan. |
| `2` | Invalid usage (adapter bug) | Treat as MANUAL and flag the bug in the summary. |
| `3` | Upstream API / network failure | Mark REVIEW MANUALLY with reason from stderr. **For `bitbucket` specifically**, exit 3 with an empty `$OUT.patch` means `/diff/` timed out — `$OUT-meta.json` (commits + filenames) is still populated and usable for a MEDIUM-only scan. |

**Heuristic scan** — apply the same patterns to every kind by grepping `$OUT.patch` and reading `$OUT-meta.json`. Only `^+` lines (additions) count; never alert on removals. The **author cross-check** for unknown contributors is GitHub-only (`gh api repos/<owner>/<repo>/commits?author=<login>&per_page=5`); for gitlab/bitbucket/git, skip it and note "author cross-check unavailable" in the summary.

Scan patches for:

**HIGH severity (flag as DO NOT UPGRADE):**
- New `curl`, `wget`, `Invoke-WebRequest` piped into a shell (`| bash`, `| sh`, `| powershell`)
- New dynamic execution primitives applied to anything that could be attacker-controlled — in particular `eval`, `exec`, shell-invoking process runners (`system`, `popen`, Python's `subprocess` with `shell=True`, Ruby backticks), Lua `loadstring`/`assert(loadstring(...))`, `vim.fn.system`
- Reads of credential-bearing paths: `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.netrc`, `.env`, `*_token*`, `*_key*`, shell history files
- Large inline base64 / hex / long numeric blobs (>200 chars, suggestive of obfuscated payload)
- Network endpoints to domains not obviously associated with the project
- Commits by an author who does not appear elsewhere in the repo's recent history (cross-check via `gh api repos/<owner>/<repo>/commits?author=<login>&per_page=5`)

**MEDIUM severity (flag as REVIEW MANUALLY):**
- Unexpectedly large addition of unrelated files (>20 new files in a non-refactor release)
- Binary file additions
- New runtime dependencies in build files (`package.json`, `Cargo.toml`, `go.mod`, configure scripts)
- Significant non-source-language file additions (e.g. a pure-C project suddenly gaining `.py` build glue)

**LOW / clean:**
- README / docs only
- Syntax / type / doc-comment fixes
- Test additions
- Refactors within existing files

Downgrade **UPDATE** to **REVIEW MANUALLY** on MEDIUM findings or to **DO NOT UPGRADE** on HIGH findings. For **SECURITY**, keep the classification but surface HIGH findings prominently — the user still needs to know.

### 7. Chat summary

Print one compact block, grouped by classification:

```
Processed N formula(s):

SECURITY (upgrade recommended regardless of age):
  <name> <old> → <new>  CVE(s): <CVE-IDs>  Diff: <clean | N flags>

UPDATE (≥10d old, diff clean):
  <name> <old> → <new>  Age: <X>d  Diff: clean

REVIEW MANUALLY:
  <name> <old> → <new>  Reason: <MEDIUM finding summary>

WAIT (<10d old):
  <name> <old> → <new>  Age: <X>d — try again in <10-X>d

DO NOT UPGRADE:
  <name> <old> → <new>  Reason: <HIGH finding summary>

MANUAL (upstream diff unavailable):
  <name>  Reason: <upstream not resolvable | tag not found | upstream unreachable>

Casks (not analyzed):
  <name1>, <name2>, ...

---
Upgrade command (SECURITY + UPDATE only):
  brew upgrade <name1> <name2> <name3>
```

Omit sections that are empty. If there are no approved upgrades, omit the final command block entirely and say so explicitly.

### 8. Persist the report

After printing the chat summary, also save it as Markdown to `$HOME/dotfiles/.local/brew-review-$(date +%F).md` so the user has a durable record. `.local/` is gitignored at the dotfiles repo root, so the file is kept alongside the repo without being committed. Run `mkdir -p "$HOME/dotfiles/.local"` first — the directory does not exist on a fresh checkout.

Format the file as proper Markdown (tables for each classification, fenced code block for the upgrade command) rather than the compact monospace block printed to chat. The file is written even if there are no approved upgrades, so the user can see what was deferred and why. If a same-day file already exists, overwrite it — the latest run is canonical.

## Failure modes

- **grype DB download fails** (first run, or when the cached DB on the machine is stale / offline): report "CVE scan unavailable — falling back to no security classification", then process every formula through the age gate only. Still useful, just less informative. To preempt this on a fresh machine, run `grype db update` once before the first `/review-brew-outdated` invocation.
- **`gh api compare` 404s** (force-pushed or rewritten history upstream): classify as **MANUAL** with reason "upstream compare unavailable".
- **GitHub rate limit** (403 with `x-ratelimit-remaining: 0`): stop processing, report remaining formulae as skipped with the reason "github rate limit".
- **GitLab API returns `{"message":"404 ..."}` or `{"message":"403 ..."}`**: the project path is wrong (private fork, renamed repo) or the instance requires auth. Classify as **MANUAL** with the returned message as the reason.
- **Bitbucket `/diff/` times out** (Atlassian edge occasionally 504s on large spans like x265 4.1→4.2 = 1.7 MB patch): retry once with `curl --max-time 30`, then fall back to diffstat-only review — set the meta file, leave the patch empty, and mark the formula REVIEW MANUALLY with reason "bitbucket diff unavailable".
- **`git clone` / `git fetch` for cgit fails** (upstream server offline, network): classify as **MANUAL** with reason "upstream git unreachable". Do NOT delete the cache — a stale cache is better than nothing for the next run.
- **Tag contains `/`** (e.g. `release/x.y`, `refs/tags/foo/bar`): `contains($v)` still matches, but URL-encode the tag when embedding in API paths — GitLab `compare?from=<tag>` accepts URL-encoded refs.
- **`brew info` returns no JSON** (formula renamed or removed): classify as **MANUAL**.

## Why these choices

- **syft + grype over keyword heuristics.** A grep-for-"CVE" over release notes misses advisories that were fixed silently and flags prose that just mentions past incidents. Advisory databases are authoritative and cheap to query.
- **10-day gate kept from Renovate policy.** The rest of this repo (`lazy-lock.json`, `aqua.yaml`) already uses `minimumReleaseAge: 10 days` via Renovate. Matching the threshold here keeps expectations consistent.
- **No automatic `brew upgrade`.** Homebrew upgrades touch `/opt/homebrew` and can trigger cascading dependency upgrades. The user runs the command so they can eyeball it and interrupt if something looks off.
- **Cellar-wide syft scan.** Per-formula scans would duplicate work; one pass is O(minutes) and feeds every downstream decision.
- **Host adapters instead of github-only.** Many Homebrew formulae (every GNU project, VideoLAN libs, x265, inria libs) live outside GitHub. Leaving them MANUAL was pushing ~30% of `brew outdated` into untriaged territory. GitLab and Bitbucket both expose a compare-equivalent API; cgit/Savannah doesn't, but a shallow bare clone at `/tmp/brew-review-cache/` works everywhere and gives local `git diff` access — the same heuristic grep then applies uniformly.
- **Patch-file + meta-file split.** Each adapter produces different JSON shapes, but the HIGH heuristics are purely patch-text regexes. Normalizing to `/tmp/brew-diff-<name>.patch` (one unified diff) + `/tmp/brew-diff-<name>-meta.json` (commits + files) lets the scan logic stay adapter-agnostic.
- **Reports saved under `.local/`, not `/tmp/`.** Chat summaries scroll away and `/tmp/` is cleared by macOS's periodic cleanup (and on reboot). `.local/` is gitignored at the dotfiles repo root, so reports persist with the repo (visible to `ls -A`, easy to grep across runs) without entering version control.
