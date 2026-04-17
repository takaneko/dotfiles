---
name: review-brew-outdated
description: Review Homebrew formulae reported by `brew outdated`, classify each update by security impact and release age, analyze the upstream diff for supply-chain red flags, and print a chat summary with a ready-to-paste `brew upgrade` command covering only the approved packages. Triggered by requests like "review brew outdated", "triage homebrew updates", "check if brew packages are safe to upgrade", or explicit /review-brew-outdated invocation.
---

# review-brew-outdated

Reviews outdated Homebrew formulae and decides which are safe to upgrade. For each candidate it:

1. Cross-references installed versions against a CVE scan (syft + grype) to flag security-relevant updates.
2. Enforces a 10-day release-age gate for non-security updates (same policy as Renovate).
3. Scans the upstream GitHub diff for supply-chain red flags (remote script exec, credential access, obfuscation, unexpected dependency pulls).
4. Prints a chat summary and a `brew upgrade` command covering only packages classified as UPDATE.

The skill never runs `brew upgrade` itself — the user runs the printed command.

## Scope

- Formulae only. Casks are listed as "manual review" in the summary but not analyzed.
- Optional package arguments: `/review-brew-outdated jq git` restricts processing to the named formulae. No arguments processes every outdated formula.
- Safe to re-run — nothing is cached between invocations.

## Required tools

`brew`, `gh` (authed), `jq`, `syft`, `grype`. All are installed via aqua (`anchore/syft`, `anchore/grype`) or available by default on the system.

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

Derive the GitHub repo (`<owner>/<repo>`) by checking these fields in order:

1. `head_url` starting with `https://github.com/` → strip prefix + `.git` suffix.
2. `stable_url` matching `https://github.com/<owner>/<repo>/...` → extract the first two path segments.
3. `homepage` matching `https://github.com/<owner>/<repo>` → use it directly.

If none match, the upstream is not a GitHub repo (SourceForge, GNU FTP, self-hosted, etc.). Record the formula as **MANUAL** (skip steps 4-6) and continue.

### 4. Resolve tag names and release date

Tag naming is not standardised across projects. Homebrew's `current_version` (e.g. `1.6.58`) may appear upstream as `v1.6.58`, `libpng-1.6.58`, `release-1.6.58`, etc. List recent tags and pick the one whose name contains the version string verbatim. Note: `gh api --jq` only takes a jq expression — it does NOT pass through jq CLI flags like `--arg`. To interpolate a shell variable into the filter, pipe through a standalone `jq` instead:

```bash
gh api "repos/<owner>/<repo>/tags?per_page=100" \
  | jq --arg v "<latest_version>" \
       '[.[] | select(.name | contains($v))] | .[0] | {name, sha: .commit.sha}'
```

Repeat for the installed version (`installed_versions[0]` — the array normally has one entry but `brew` allows multiple installed versions for versioned formulae like `python@3.10`, so pin explicitly) to get the comparison base. Fetch the tagged commit's committer date:

```bash
gh api "repos/<owner>/<repo>/commits/<NEW_SHA>" --jq '.commit.committer.date'
```

Compute age in days via `jq fromdate` (portable across BSD/GNU `date`):

```bash
jq -n --arg d "<ISO date>" '($d | fromdate) as $t | ((now - $t) / 86400) | floor'
```

If either tag cannot be resolved, record as **MANUAL** and continue — do not guess.

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

```bash
gh api "repos/<owner>/<repo>/compare/<OLD_SHA>...<NEW_SHA>" \
  --jq '{ahead: .ahead_by,
          commits: [.commits[] | {sha: .sha[0:7], author: .commit.author.name,
                                   date: .commit.author.date,
                                   message: (.commit.message | split("\n")[0])}],
          files: [.files[] | {filename, status, additions, deletions, patch}]}' \
  > /tmp/brew-diff-<name>.json
```

Inspect `/tmp/brew-diff-<name>.json` carefully. Scan patches for:

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
  <name>  Reason: <non-github homepage | tag not found>

Casks (not analyzed):
  <name1>, <name2>, ...

---
Upgrade command (SECURITY + UPDATE only):
  brew upgrade <name1> <name2> <name3>
```

Omit sections that are empty. If there are no approved upgrades, omit the final command block entirely and say so explicitly.

## Failure modes

- **grype DB download fails** (first run, or when the cached DB on the machine is stale / offline): report "CVE scan unavailable — falling back to no security classification", then process every formula through the age gate only. Still useful, just less informative. To preempt this on a fresh machine, run `grype db update` once before the first `/review-brew-outdated` invocation.
- **`gh api compare` 404s** (force-pushed or rewritten history upstream): classify as **MANUAL** with reason "upstream compare unavailable".
- **Rate limit** (403 with `x-ratelimit-remaining: 0`): stop processing, report remaining formulae as skipped with the reason "github rate limit".
- **`brew info` returns no JSON** (formula renamed or removed): classify as **MANUAL**.

## Why these choices

- **syft + grype over keyword heuristics.** A grep-for-"CVE" over release notes misses advisories that were fixed silently and flags prose that just mentions past incidents. Advisory databases are authoritative and cheap to query.
- **10-day gate kept from Renovate policy.** The rest of this repo (`lazy-lock.json`, `aqua.yaml`) already uses `minimumReleaseAge: 10 days` via Renovate. Matching the threshold here keeps expectations consistent.
- **No automatic `brew upgrade`.** Homebrew upgrades touch `/opt/homebrew` and can trigger cascading dependency upgrades. The user runs the command so they can eyeball it and interrupt if something looks off.
- **Cellar-wide syft scan.** Per-formula scans would duplicate work; one pass is O(minutes) and feeds every downstream decision.
