---
name: review-renovate-pr
description: Review open Renovate-generated PRs on this dotfiles repo that update vim plugins in lazy-lock.json. For each unreviewed PR, checks that the upstream commit is >= 10 days old, analyzes the upstream diff for supply-chain red flags (remote script exec, credential access, obfuscation, maintainer changes), posts a review comment automatically, then prints a chat summary with a merge recommendation per PR. Triggered by requests like "review the Renovate PRs", "check lazy plugin updates", "triage Renovate PRs", or explicit /review-renovate-pr invocation.
---

# review-renovate-pr

Reviews Renovate-generated PRs that update vim plugin pins in `lazy-lock.json`. Posts a review comment on each PR and reports a summary to chat.

## Scope

- Only PRs in the current repo (`takaneko/dotfiles`)
- Only PRs whose branch matches `renovate/*` (Renovate-generated)
- Only unreviewed PRs: skip any PR that already has at least one issue comment OR a label starting with `reviewed`
- Optional PR number argument: `/review-renovate-pr 21` processes just that PR

## Required tools

`gh` CLI with repo auth, `jq`. No git clone required — all diffs come from GitHub's compare API.

Run all commands from `~/dotfiles` (the skill reads `renovate-lazy.json` via relative path):
```bash
cd ~/dotfiles
```

## Steps

### 1. Determine the PR list

If the user passed a PR number, use it directly. Otherwise, enumerate open PRs whose branch starts with `renovate/` and that don't carry a `reviewed*` label:

```bash
gh pr list --state open --json number,headRefName,labels \
  --jq '.[]
    | select(.headRefName | startswith("renovate/"))
    | select([.labels[].name] | map(startswith("reviewed")) | any | not)
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

### 2. For each PR, extract the update

```bash
gh pr view <N> --json title,headRefName,baseRefName
gh pr diff <N>
```

Parse the `lazy-lock.json` diff hunk to extract:
- Plugin name (the JSON key, e.g. `telescope.nvim`)
- Old commit SHA (on the `-` line)
- New commit SHA (on the `+` line)

Look up the upstream repo URL by matching the plugin name against `renovate-lazy.json`:

```bash
jq -r --arg name "<plugin>" \
  '.customManagers[] | select(.depNameTemplate == $name) | .packageNameTemplate' \
  renovate-lazy.json
```

Strip `https://github.com/` to get `<owner>/<repo>`.

### 3. Check commit age

```bash
committer_date=$(gh api repos/<owner>/<repo>/commits/<NEW_SHA> --jq '.commit.committer.date')
age_days=$(jq -n --arg d "$committer_date" '($d | fromdate) as $t | ((now - $t) / 86400) | floor')
```

`jq fromdate` parses ISO 8601 portably (avoids BSD vs GNU `date` incompatibility). Threshold: **10 days**. Record PASS if `age_days >= 10`, else FAIL.

**If FAIL (< 10 days): skip steps 4 and 5 for this PR.** Do not run the diff review, do not post a comment. Record only the age/WAIT state for the chat summary in step 6.

### 4. Fetch and analyze the diff (age PASS only)

Skip this step if age check in step 3 failed.


```bash
gh api "repos/<owner>/<repo>/compare/<OLD_SHA>...<NEW_SHA>" \
  --jq '{
    ahead: .ahead_by,
    commits: [.commits[] | {sha: .sha[0:7], author: .commit.author.name, date: .commit.author.date, message: (.commit.message | split("\n")[0])}],
    files: [.files[] | {filename, status, additions, deletions, patch}]
  }' > /tmp/rr-<N>.json
```

Inspect `/tmp/rr-<N>.json` carefully. Scan patches for:

**HIGH severity (flag as DO NOT MERGE):**
- New `curl`, `wget`, `Invoke-WebRequest` piped into a shell (`| bash`, `| sh`, `| powershell`)
- New `eval`, `loadstring`, `load()`, `assert(loadstring(...))`, `vim.fn.execute()`, `os.execute`, `io.popen`, `os.popen`, `vim.fn.system()` / `vim.fn.systemlist()` applied to anything that could be attacker-controlled (env vars parsed from web, remote fetches, user input)
- Reads of credential-bearing paths: `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.netrc`, `.env`, `*_token*`, `*_key*`, `~/.bash_history`, `~/.zsh_history`
- Large inline base64 / hex / long numeric blobs (>200 chars, suggestive of obfuscated payload)
- New network endpoints (domains not obviously associated with the plugin's purpose)
- Commit author identity changed to an unknown account (new commits by someone other than the plugin's usual maintainers — cross-check against `commits[].author`)

**MEDIUM severity (flag as REVIEW MANUALLY):**
- Unexpectedly large addition of unrelated files (>20 new files in a non-refactor commit)
- Binary file additions
- New dependencies in plugin manifests (e.g., a Lua plugin suddenly pulling a native library)
- Added `dependencies` entries to the plugin's own lazy.nvim spec
- Significant non-lua/vim file additions (.py, .rs, .go, .sh where the plugin is pure vim)

**LOW / clean:**
- README / docs only
- Syntax / type / doc-comment fixes
- Test additions
- Refactors touching existing files only

### 5. Post the review comment (age PASS only)

Skip this step if age check in step 3 failed. Review comments are only posted once a PR has cleared the 10-day gate.

Build the comment body using this template (include the HTML marker so we can detect our own comments in the future):

```markdown
<!-- review-renovate-pr -->
## Renovate PR review

| Check | Result |
|---|---|
| Plugin | `<owner>/<repo>` (`<plugin>`) |
| Update | `<OLD_SHORT>` → `<NEW_SHORT>` |
| Commits ahead | <ahead_by> |
| New commit age | <age> days — PASS |
| Files changed | <count> |
| Diff review | <clean / N findings> |

### Diff findings
<itemized findings with file:line references, or "No red flags detected.">

### Recommendation
**<MERGE OK | REVIEW MANUALLY | DO NOT MERGE>**

<one-sentence reason>

---
*Generated by `review-renovate-pr` skill.*
```

Post automatically:

```bash
gh pr comment <N> --body "$(cat <<'EOF'
<body>
EOF
)"
```

### 6. Chat summary

After processing all PRs, print one compact block:

```
Processed N Renovate PR(s):

#<N> <plugin> (<old7>..<new7>)
  Age: <X>d ✓  Diff: <clean|N flags>  → <MERGE OK|REVIEW|DO NOT MERGE>  (comment posted)

#<N> <plugin> (<old7>..<new7>)
  Age: <X>d ✗  → WAIT (comment skipped)

...
```

Do NOT merge any PR. The skill's job ends at the comment + summary.

## Recommendation table

| Age check | Diff review | Action |
|---|---|---|
| FAIL (<10d) | (not performed) | No comment posted. Chat summary reports WAIT. |
| PASS (>=10d) | clean | Comment posted → MERGE OK |
| PASS | MEDIUM flags | Comment posted → REVIEW MANUALLY |
| PASS | HIGH flags | Comment posted → DO NOT MERGE |

## Force re-review

To re-review a PR that was already reviewed:
- Delete the comment containing `<!-- review-renovate-pr -->`, or
- Remove the `reviewed` label (if one was added manually)

## Failure modes

- If `gh pr diff` returns an empty diff: the PR may be in an odd state — note in summary, skip review comment, skip.
- If the upstream repo cannot be resolved from `renovate-lazy.json`: skip with a chat note; don't guess.
- If `gh api compare` 404s (commit unavailable or force-pushed): report as "upstream diff unavailable" and recommend manual review.
- Rate limit (403 with `x-ratelimit-remaining: 0`): stop processing, report remaining PRs as skipped.
