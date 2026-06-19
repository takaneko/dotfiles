---
name: review-renovate-pr
description: Review open Renovate-generated PRs on this dotfiles repo. Covers two PR types — vim plugin pins in lazy-lock.json (digest/commit-pinned) and CLI tool versions in aqua.yaml (tag-pinned). For each unreviewed PR, checks that the upstream commit/tag is >= 10 days old, analyzes the upstream diff for supply-chain red flags (remote script exec, credential access, obfuscation, maintainer changes, compromised release pipelines), posts a review comment automatically, then prints a chat summary with a merge recommendation per PR. For lazy PRs whose tip SHA is too recent, falls back to reviewing the newest intermediate commit >=10d old and surfaces it as a hand-pin candidate. For aqua PRs, also flags when the PR lacks the regenerated aqua-checksums.json (needed for merge). Triggered by requests like "review the Renovate PRs", "check lazy plugin updates", "triage aqua updates", "triage Renovate PRs", or explicit /review-renovate-pr invocation.
---

# review-renovate-pr

Reviews Renovate-generated PRs that update **either** vim plugin pins in `lazy-lock.json` (digest/commit-pinned) **or** CLI tool versions in `aqua.yaml` (tag-pinned). Posts a review comment on each PR and reports a summary to chat.

## Scope

- Only PRs in the current repo (`takaneko/dotfiles`)
- Only PRs whose branch matches `renovate/*` (Renovate-generated)
- Two reviewable PR types, distinguished by which file the diff touches:
  - **lazy** — `lazy-lock.json` digest bumps (vim plugins)
  - **aqua** — `aqua.yaml` tag bumps (CLI tools)
  - Anything else (e.g. `renovate.json5` preset bumps like `aquaproj/aqua-renovate-config`, or `.github/workflows/*` action bumps) is **out of scope**: note it in the summary and skip (no upstream-diff review, no comment).
- Only unreviewed PRs: skip any PR that already has a `<!-- review-renovate-pr -->` comment OR a label starting with `reviewed`, or a `wait` label
- Optional PR number argument: `/review-renovate-pr 21` processes just that PR

## Required tools

`gh` CLI with repo auth, `jq`. No git clone required — all diffs come from GitHub's compare API.

- **lazy** PRs resolve the upstream repo from `renovate-lazy.json` (relative path → run from `~/dotfiles`).
- **aqua** PRs derive the upstream repo from the package name in the `aqua.yaml` hunk.

```bash
cd ~/dotfiles
```

## Steps

### 1. Determine the PR list

If the user passed a PR number, use it directly. Otherwise, enumerate open PRs whose branch starts with `renovate/` and that don't carry a `reviewed*` label or a `wait` label (the latter lets the user suppress repeat intermediate-fallback proposals — see step 7.3):

```bash
gh pr list --state open --json number,headRefName,labels \
  --jq '.[]
    | select(.headRefName | startswith("renovate/"))
    | select([.labels[].name] | map(startswith("reviewed") or . == "wait") | any | not)
    | .number'
```

(Do NOT filter by comment count here — `gh pr list`'s `comments` field semantics vary between gh versions. Use the per-PR marker check in step 2 instead.)

For each candidate PR number, check for a prior self-review comment:

```bash
gh pr view <N> --json comments \
  --jq '[.comments[] | select(.body | contains("<!-- review-renovate-pr -->"))] | length'
```

If the result is >= 1, skip that PR.

If the remaining list is empty, tell the user "No unreviewed Renovate PRs." and stop.

### 2. Classify each PR and extract the update

```bash
gh pr view <N> --json title,headRefName,baseRefName
gh pr diff <N> --name-only   # which files changed → classify
gh pr diff <N>               # the hunks
```

Classify by the changed file:
- contains `lazy-lock.json` → **lazy** PR → step 2.1
- contains `aqua.yaml` → **aqua** PR → step 2.2
- neither → out of scope; record in summary as `SKIP (not a lazy/aqua PR)` and move on.

#### 2.1 lazy PR extraction

Parse the `lazy-lock.json` diff hunk to extract:
- Plugin name (the JSON key, e.g. `telescope.nvim`)
- Old commit SHA (on the `-` line) → `OLD_REF`
- New commit SHA (on the `+` line) → `NEW_REF`

Look up the upstream repo URL by matching the plugin name against `renovate-lazy.json`:

```bash
jq -r --arg name "<plugin>" \
  '.customManagers[] | select(.depNameTemplate == $name) | .packageNameTemplate' \
  renovate-lazy.json
```

Strip `https://github.com/` to get `<owner>/<repo>`. This PR type is **digest-tracking**, so the intermediate-SHA fallback (step 7) applies.

#### 2.2 aqua PR extraction

Parse the `aqua.yaml` diff hunk:
- `-  - name: <pkg>@<OLD_TAG>` → `OLD_REF=<OLD_TAG>`
- `+  - name: <pkg>@<NEW_TAG>` → `NEW_REF=<NEW_TAG>`

`<pkg>` is the aqua package name, e.g. `caddyserver/caddy`, `kubernetes/kubernetes/kubectl`, `jqlang/jq` (tags can be non-`v` prefixed, e.g. `jq-1.8.1`, `bun-v1.3.14`).

Resolve the upstream GitHub repo: take the **first two path segments** of `<pkg>` as `<owner>/<repo>` (so `kubernetes/kubernetes/kubectl` → `kubernetes/kubernetes`). Confirm it exists by **exit code** — `gh api` prints the 404 error body to stdout, so don't test for empty output:

```bash
if gh api repos/<owner>/<repo> >/dev/null 2>&1; then echo github; else echo non-github; fi
```

- If `non-github`, the package is **not GitHub-backed** (e.g. `1password/cli` is fetched over HTTP from a vendor CDN). Skip the upstream diff (step 4): record `upstream diff unavailable (non-GitHub datasource)`, recommend manual review against the vendor's release notes, and note that the `aqua-checksums.json` SHA256 is the real integrity control here. Still post a comment with the age result if obtainable, else mark the age check `n/a`.

The compare refs are the **tags themselves**. `gh api repos/<owner>/<repo>/commits/<TAG>` resolves a tag to its commit (used for the age check), and `compare/<OLD_TAG>...<NEW_TAG>` works on tag names.

This PR type is **tag-pinned**, so the intermediate-SHA fallback (step 7) does **not** apply (see step 7 scope).

**Checksum-presence check (aqua only):** record whether the PR already regenerated the checksums.

```bash
gh pr diff <N> --name-only | grep -qx aqua-checksums.json && echo present || echo missing
```

PRs created after the `postUpgradeTasks`/`aqua upc` hook landed include `aqua-checksums.json` automatically (`present`). Older backlog PRs are `missing` and need `aqua upc -a --prune` run on the branch before merge, or `aqua install` fails (`require_checksum: true`). Surface this in the comment and summary; it does **not** by itself change the MERGE/REVIEW/DO-NOT-MERGE verdict.

### 3. Check age

Works for both PR types — `OLD_REF`/`NEW_REF` is a commit SHA (lazy) or a tag (aqua); `gh api .../commits/<ref>` resolves either.

```bash
committer_date=$(gh api repos/<owner>/<repo>/commits/<NEW_REF> --jq '.commit.committer.date')
age_days=$(jq -n --arg d "$committer_date" '($d | fromdate) as $t | ((now - $t) / 86400) | floor')
```

`jq fromdate` parses ISO 8601 portably (avoids BSD vs GNU `date` incompatibility). Threshold: **10 days**. Record PASS if `age_days >= 10`, else FAIL.

**If FAIL (< 10 days): skip steps 4 and 5 for this PR.** Do not run the diff review, do not post a comment.
- **lazy** PR → run the **Intermediate-SHA fallback** (step 7).
- **aqua** PR → no fallback (step 7 scope); just record WAIT.

Record the age/WAIT state (plus any fallback findings) for the chat summary in step 6.

### 4. Fetch and analyze the diff (age PASS only)

Skip this step if age check in step 3 failed, or (aqua) if the package is non-GitHub-backed.

```bash
gh api "repos/<owner>/<repo>/compare/<OLD_REF>...<NEW_REF>" \
  --jq '{
    ahead: .ahead_by,
    commits: [.commits[] | {sha: .sha[0:7], author: .commit.author.name, date: .commit.author.date, message: (.commit.message | split("\n")[0])}],
    files: [.files[] | {filename, status, additions, deletions, patch}]
  }' > /tmp/rr-<N>.json
```

Inspect `/tmp/rr-<N>.json` carefully. Scan patches for:

**HIGH severity (flag as DO NOT MERGE) — applies to both PR types:**
- New `curl`, `wget`, `Invoke-WebRequest` piped into a shell (`| bash`, `| sh`, `| powershell`)
- New `eval`, `loadstring`, `load()`, `assert(loadstring(...))`, `vim.fn.execute()`, `os.execute`, `io.popen`, `os.popen`, `vim.fn.system()` / `vim.fn.systemlist()` applied to anything that could be attacker-controlled (env vars parsed from web, remote fetches, user input)
- Reads of credential-bearing paths: `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.netrc`, `.env`, `*_token*`, `*_key*`, `~/.bash_history`, `~/.zsh_history`
- Large inline base64 / hex / long numeric blobs (>200 chars, suggestive of obfuscated payload)
- New network endpoints (domains not obviously associated with the project's purpose)
- Commit author identity changed to an unknown account (new commits by someone other than the project's usual maintainers — cross-check against `commits[].author`)

**MEDIUM severity (flag as REVIEW MANUALLY):**
- _lazy_: Significant non-lua/vim file additions (`.py`, `.rs`, `.go`, `.sh` where the plugin is pure vim); added `dependencies` to the plugin's lazy.nvim spec; a Lua plugin suddenly pulling a native library
- _aqua_: changes to the tool's **release/build pipeline or install scripts** (`.github/workflows/*release*`, `.goreleaser.*`, `install.sh`, publish-time `Dockerfile`s) — because aqua downloads the resulting release asset, a compromised release pipeline is the relevant supply-chain vector. (The binary content itself is still pinned by `aqua-checksums.json` SHA256, which is your backstop.) Do **NOT** flag normal source files in the tool's own language (`.go`/`.rs`/`.ts`/…) — unlike vim plugins, these tools are legitimately polyglot.
- _both_: unexpectedly large addition of unrelated files (>20 new files in a non-refactor commit); binary file additions

**LOW / clean (both):** README/docs only; syntax/type/doc-comment fixes; test additions; refactors touching existing files only.

**Diff too large:** mega-repos (e.g. `kubernetes/kubernetes`) produce compares with hundreds of commits / GitHub truncates at 250 commits & 300 files. If `ahead` is very large or the file list is obviously truncated, do not pretend to have scanned it: record `diff too large for automated scan` → **REVIEW MANUALLY**, and lean on the release notes + the `aqua-checksums.json` pin.

### 5. Post the review comment (age PASS only)

Skip this step if age check in step 3 failed. Review comments are only posted once a PR has cleared the 10-day gate.

Build the comment body using this template (include the HTML marker so we can detect our own comments in the future). Use **Package** for the row label in both cases; for lazy PRs the value is `<owner>/<repo>` (`<plugin>`), for aqua PRs it is `<owner>/<repo>` (`<pkg>`). `<OLD_DISP>`/`<NEW_DISP>` are the short SHAs (lazy) or the tags (aqua).

```markdown
<!-- review-renovate-pr -->
## Renovate PR review

| Check | Result |
|---|---|
| Type | <lazy | aqua> |
| Package | `<owner>/<repo>` (`<plugin-or-pkg>`) |
| Update | `<OLD_DISP>` → `<NEW_DISP>` |
| Commits ahead | <ahead_by | n/a> |
| New <commit|tag> age | <age> days — PASS |
| Files changed | <count> |
| Diff review | <clean / N findings / too large / unavailable> |
| Checksum in PR | <yes | no — run `aqua upc -a --prune` before merge | n/a (lazy)> |

### Diff findings
<itemized findings with file:line references, or "No red flags detected.">

### Recommendation
**<MERGE OK | REVIEW MANUALLY | DO NOT MERGE>**

<one-sentence reason>

---
*Generated by `review-renovate-pr` skill.*
```

For an **aqua** PR where `Checksum in PR` is `no`, append to the reason: "merge requires regenerating `aqua-checksums.json` first (`aqua upc -a --prune` on the branch, commit, then merge)."

Post automatically:

```bash
gh pr comment <N> --body "$(cat <<'EOF'
<body>
EOF
)"
```

### 6. Chat summary

After processing all PRs, print one compact block. Show the type and (for aqua) the checksum state.

```
Processed N Renovate PR(s):

#<N> [lazy] <plugin> (<old7>..<new7>)
  Age: <X>d ✓  Diff: <clean|N flags>  → <MERGE OK|REVIEW|DO NOT MERGE>  (comment posted)

#<N> [aqua] <pkg> (<OLD_TAG> → <NEW_TAG>)
  Age: <X>d ✓  Diff: <clean|N flags|too large>  Checksum: <in-PR|MISSING>  → <verdict>  (comment posted)

#<N> [lazy] <plugin> (<old7>..<new7>)
  Age: <X>d ✗  → WAIT (comment skipped)
  Intermediate <int7> (<Y>d, <ahead> commits): clean → APPLIABLE

#<N> [aqua] <pkg> (<OLD_TAG> → <NEW_TAG>)
  Age: <X>d ✗  → WAIT (comment skipped; tag-pinned, no intermediate)

#<N> [skip] <branch> — not a lazy/aqua PR

...
```

(`<new7>` = the lazy PR's tip SHA, i.e. the value on the `+` line of the lazy-lock.json diff hunk; `<int7>` = the chosen intermediate SHA from step 7.1.)

Do NOT merge any PR. Do NOT edit `lazy-lock.json` / `aqua.yaml` / `aqua-checksums.json` or close any PR. The skill's job ends at the comment + summary + (for the lazy fallback) presenting the appliable candidate to the user.

### 7. Intermediate-SHA fallback (lazy, age FAIL only)

When step 3 reports FAIL for a **lazy** PR, the tip SHA is too recent — but an *earlier* commit in the same compare range may already satisfy the threshold. In active repos (e.g. nvim-lspconfig, vimdoc-ja), waiting for the tip to age out is a moving target because Renovate force-pushes the PR to the latest HEAD on each weekly run. The fallback finds the newest intermediate commit that has aged out, runs the same red-flag diff review against `OLD_REF..INTERMEDIATE_SHA`, and surfaces it as a hand-pin candidate.

**Scope**: only digest-tracking **lazy** PRs. **aqua** tag-pinned PRs have no arbitrary-commit pin — aqua pins tags, not SHAs — so on age FAIL just report WAIT (no fallback). (Optional: if an intermediate *tag* in the range has aged out — e.g. old `v0.30.0` → new `v0.32.0` with `v0.31.0` ≥10d old — you MAY surface that intermediate tag as a hand-pin candidate, but do not auto-apply.)

#### 7.1 Find the newest qualifying intermediate commit

GitHub's compare API lists commits oldest-first. Iterate from newest backward; the first commit whose age clears the step 3 threshold (currently 10 days — keep the `-ge 10` literal below in sync if step 3 changes) wins:

```bash
gh api "repos/<owner>/<repo>/compare/<OLD_REF>...<NEW_REF>" \
  --jq '[.commits[] | "\(.commit.committer.date)\t\(.sha)"] | reverse | .[]' \
| while IFS=$'\t' read -r d sha; do
    age=$(jq -n --arg d "$d" '($d|fromdate) as $t | ((now - $t)/86400) | floor')
    if [ "$age" -ge 10 ]; then echo "$sha $d ${age}d"; break; fi
  done
```

If the loop produces no output, no qualifying intermediate exists — record the WAIT state with `Intermediate: (none ≥ threshold in <total> commits)` and stop the fallback for this PR.

#### 7.2 Diff-review the intermediate range

Run the **same** patch-scan as step 4, but against `OLD_REF..INTERMEDIATE_SHA`. Use the same jq spec as step 4 so the on-disk shape matches and the same red-flag heuristics apply:

```bash
gh api "repos/<owner>/<repo>/compare/<OLD_REF>...<INTERMEDIATE_SHA>" \
  --jq '{
    ahead: .ahead_by,
    commits: [.commits[] | {sha: .sha[0:7], author: .commit.author.name, date: .commit.author.date, message: (.commit.message | split("\n")[0])}],
    files: [.files[] | {filename, status, additions, deletions, patch}]
  }' > /tmp/rr-<N>-int.json
```

Apply the same HIGH/MEDIUM/LOW classification from step 4. Do **not** post a PR comment — the open PR still tracks the unreviewed tip SHA, and a comment claiming approval would be misleading.

#### 7.3 Surface the candidate in chat

Include the intermediate result in the step 6 chat summary line for that PR. If the intermediate diff is **clean (APPLIABLE)**, also print the exact opt-in commands the user can authorize, plus a hint for suppressing repeat proposals:

```
To apply PR #<N> via intermediate pin:
  1. Edit lazy-lock.json: "<plugin>": commit "<OLD>" → "<INTERMEDIATE>"
  2. gh pr close <N> --comment "Superseded by direct pin to reviewed intermediate SHA <int7>."

To skip this proposal on future skill runs (without applying):
  gh pr edit <N> --add-label wait
```

The `wait` label is honored by step 1's PR enumeration filter, so subsequent invocations will not re-propose the same intermediate until the label is removed (or Renovate force-pushes the PR, which usually drops the label).

**Hard rule**: do not auto-edit `lazy-lock.json` and do not auto-close any PR. Wait for the user to explicitly say "apply" / "yes" / equivalent before performing either action.

## Recommendation table

| PR type | Age check (tip/new tag) | Intermediate fallback | Diff review | Action |
|---|---|---|---|---|
| lazy | PASS (>=10d) | — | clean | Comment posted → MERGE OK |
| lazy | PASS | — | MEDIUM flags | Comment posted → REVIEW MANUALLY |
| lazy | PASS | — | HIGH flags | Comment posted → DO NOT MERGE |
| lazy | FAIL (<10d) | none qualifies | (not performed) | No comment. Chat summary reports WAIT. |
| lazy | FAIL | intermediate found | clean | No comment. Chat surfaces APPLIABLE intermediate + opt-in commands; user authorizes. |
| lazy | FAIL | intermediate found | MEDIUM/HIGH flags | No comment. Chat surfaces DO NOT APPLY; WAIT. |
| aqua | PASS | n/a | clean (checksum in-PR) | Comment posted → MERGE OK |
| aqua | PASS | n/a | clean (checksum MISSING) | Comment posted → MERGE OK *after* `aqua upc -a --prune` on the branch |
| aqua | PASS | n/a | MEDIUM/HIGH or too large | Comment posted → REVIEW MANUALLY / DO NOT MERGE |
| aqua | PASS | n/a | unavailable (non-GitHub) | Comment posted → REVIEW MANUALLY against vendor release notes; checksum pin is the control |
| aqua | FAIL | n/a (tag-pinned) | (not performed) | No comment. Chat reports WAIT. |

## Force re-review

To re-review a PR that was already reviewed or suppressed:
- Delete the comment containing `<!-- review-renovate-pr -->` (added by step 5 on age PASS reviews), or
- Remove the `reviewed*` label (if one was added manually), or
- Remove the `wait` label (added via the step 7.3 hint to suppress repeat intermediate-fallback proposals): `gh pr edit <N> --remove-label wait`

## Failure modes

- If `gh pr diff` returns an empty diff: the PR may be in an odd state — note in summary, skip review comment, skip.
- (lazy) If the upstream repo cannot be resolved from `renovate-lazy.json`: skip with a chat note; don't guess.
- (aqua) If the package is not GitHub-backed (`gh api repos/<owner>/<repo>` 404s — e.g. `1password/cli`): skip the upstream diff, recommend manual review against the vendor's release notes, and note the `aqua-checksums.json` SHA256 is the integrity control. Still post a comment with the age result.
- (aqua) Path-style package names (`owner/repo/subpath`, e.g. `kubernetes/kubernetes/kubectl`): the repo is the first two segments.
- (aqua) Mega-repo / truncated compare: record `diff too large for automated scan` → REVIEW MANUALLY.
- (aqua) `aqua-checksums.json` missing from the PR is **not** a red flag — it just means the bump predates the `aqua upc` postUpgrade hook; flag that `aqua upc -a --prune` must run before merge.
- If `gh api compare` 404s (commit/tag unavailable or force-pushed): report as "upstream diff unavailable" and recommend manual review.
- Rate limit (403 with `x-ratelimit-remaining: 0`): stop processing, report remaining PRs as skipped.
