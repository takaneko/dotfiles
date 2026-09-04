---
name: review-brew-outdated
description: Review Homebrew formulae reported by `brew outdated`, classify each update by security impact and release age, analyze the upstream diff for supply-chain red flags, and print a chat summary with a ready-to-paste `brew upgrade` command covering only the approved packages. Triggered by requests like "review brew outdated", "triage homebrew updates", "check if brew packages are safe to upgrade", or explicit /review-brew-outdated invocation.
---

# review-brew-outdated

Reviews outdated Homebrew formulae and decides which are safe to upgrade. For each candidate it:

1. Cross-references installed versions against a CVE scan (syft + grype) to flag security-relevant updates.
2. Checks three disjoint advisory sources for whether the release *itself* fixes a published vulnerability, because grype systematically misses fresh fixes in Homebrew C/C++ libraries. A hit outranks the age gate.
3. Enforces a 10-day release-age gate for non-security updates (same policy as Renovate).
4. Scans the upstream diff for supply-chain red flags (remote script exec, credential access, obfuscation, unexpected dependency pulls). Host-aware: GitHub, GitLab, Bitbucket Cloud, and generic git (cgit / self-hosted) are all supported via per-kind adapters.
5. Prints a chat summary and a `brew upgrade` command covering only approved packages.

The skill never runs `brew upgrade` itself — the user runs the printed command.

## Reference files

`$SKILL_DIR` is `$HOME/dotfiles/.agents/skills/review-brew-outdated` (`.claude/skills` symlinks
there). Read a reference **when its trigger fires** — the happy path needs none of them.

| File | Read it when |
|---|---|
| `references/adapters.md` | A tag returns `{}` or looks wrong; an adapter exits non-zero; you need the adapter calling convention, exit codes, or the date-parsing fallback |
| `references/failure-modes.md` | Anything fails, returns empty, or looks like a malfunction — check here before concluding "clean" |
| `references/evidence.md` | A step looks like overkill; results contradict what this file says to expect; you are about to change a design decision |

## Scope

- Formulae only. Casks are listed as "manual review" in the summary but not analyzed.
- Optional package arguments: `/review-brew-outdated jq git` restricts processing to the named formulae. No arguments processes every outdated formula.
- Safe to re-run — per-run artefacts under `/tmp/brew-*.{json,patch}` are overwritten each time. The `git` adapter's bare-clone cache persists across invocations for speed and is safe to delete.

## Required tools

`brew`, `gh` (authed), `jq`, `syft`, `grype`, `curl`, `git`. Step 4a also queries `api.osv.dev` over
plain `curl` — no account, no token. All are installed via aqua (`anchore/syft`, `anchore/grype`) or
available by default.

`gdate` (GNU coreutils, via brew) is preferred for the step-4 age computation but not required —
`references/adapters.md` carries a BSD `date` fallback for machines without it.

Adapters run as child processes and cannot see a 1Password `gh` shell-plugin wrapper;
`adapters/github.sh` handles that itself, so nothing needs doing per-run. Details in
`references/adapters.md`.

## Steps

### 1. Collect the outdated list

```bash
brew outdated --json=v2 --formula > /tmp/brew-outdated.json
jq '.formulae | length' /tmp/brew-outdated.json
brew outdated --json=v2 --cask | jq '.casks | map(.name)' > /tmp/brew-outdated-casks.json
```

Each entry has `name`, `installed_versions` (array), `current_version` (despite the name, the
**latest available** version). Filter by CLI arguments if any were passed; otherwise take all.

If the formula list is empty, tell the user "No outdated formulae.", list any casks as "manual
review", and stop.

### 2. Scan installed packages for known CVEs

The most expensive step — run it once, before per-package work. The SBOM covers the entire Cellar.

```bash
HOMEBREW_CELLAR="$(brew --cellar)"
syft "$HOMEBREW_CELLAR" -o cyclonedx-json > /tmp/brew-sbom.json 2>/dev/null
grype sbom:/tmp/brew-sbom.json -o json > /tmp/brew-cves.json 2>/dev/null

# DB age — from the scan's own output. Never from a concurrent `grype db status`, which
# races grype's auto-update and reports the pre-update cache.
jq -c '.descriptor.db.status | {built, valid}' /tmp/brew-cves.json
```

Build a map from formula name → CVE matches (brew packages only — syft also catalogs deps vendored
inside bottles, which `brew upgrade` cannot act on):

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

The trailing `// {}` matters: with zero brew matches `add` returns `null`, and downstream `has()` /
`keys` against `null` would abort the run.

Any formula present as a key is a **SECURITY** candidate. An empty `fix` array does not disqualify
it — upstream databases lag new releases.

> **A grype miss is never evidence of safety.** Homebrew C/C++ libraries have no purl→advisory
> mapping and match only after NVD assigns a CPE, weeks to months later. On a confirmed-current DB
> it missed 30 advisories across four formulae. Step 4a is the compensating control.

### 3. Resolve each formula's upstream

```bash
brew info --json=v2 <name> | jq '.formulae[0] | {homepage, stable_url: .urls.stable.url, head_url: .urls.head.url}'
```

Classify into one of four **kinds** and record `{kind, key}`. Check `head_url`, then `stable_url`,
then `homepage`; first match wins:

| Kind | URL pattern | Key (args passed to adapter) |
|---|---|---|
| `github` | `https?://github\.com/<owner>/<repo>` | `<owner>/<repo>` |
| `gitlab` | `https?://<host>/<project_path>` where `<host>` starts with `gitlab.` or is in the known-GitLab list (`code.videolan.org`, `salsa.debian.org`, `foss.heptapod.net`) | `<host> <project_path>` — slash-joined namespace and repo; adapters URL-encode it |
| `bitbucket` | `https?://bitbucket\.org/<workspace>/<repo>` | `<workspace> <repo_slug>` — strip trailing `.git`, `/src/...`, `/downloads/...` |
| `git` | URL ends in `.git` on any other host, **or** homepage is `https://www.gnu.org/software/<name>/` (fallback: probe `https://git.savannah.gnu.org/git/<name>.git` with `git ls-remote --exit-code`; some GNU projects live on `git.gnunet.org`) | `<name> <clone_url>` — `<name>` is the formula name, used as the cache key |

**Homepages that name no repository.** Several formulae publish only tarballs from a project-owned
host, so no row above matches and they fall to MANUAL despite having a reviewable upstream. Knowing
the mirror makes most of them ordinary `github` kind, with `nss` the noted exception:

| Homepage / stable_url host | Key |
|---|---|
| `gnupg.org`, `www.gnupg.org` | `gpg/<formula>` — `gpg/gnupg`, `gpg/gpgme`, `gpg/libgcrypt`. **`gpgmepp` is its own repo `gpg/gpgmepp`**, not a subdirectory of `gpg/gpgme`, and its tags (`gpgmepp-2.2.0`) track a separate cadence. |
| `ftp.mozilla.org/pub/security/nss`, `firefox-source-docs.mozilla.org` | `mozilla/nss` (`nss-dev/nss` redirects here) — **the adapter cannot resolve this one**; see step 4. Tags are `NSS_3_128_RTM`. |

Do **not** spend probes on `git.gnupg.org` or `dev.gnupg.org`: both refused `git ls-remote` for
gnupg, gpgme, libgcrypt and gpgmepp on 2026-09-03. The GitHub mirror is the only working path.

If none match, try the **tarball fallback** (§3a); only if that is not applicable, record **MANUAL**
with reason "upstream not resolvable" and skip steps 4–6.

**Brew-revision-only bumps** (`8.1` → `8.1_1`, `1.86.0` → `1.86.0_1`): the upstream version is
unchanged — only the Homebrew formula revision bumped. Both versions resolve to the same tag and
`compare` returns an empty diff. Record as UPDATE with reason "brew revision only, no upstream
diff" and skip the heuristic scan. Do NOT classify as MANUAL. If the revision bump log cites another
formula ("revision bump for x265 4.2"), note the dependency so the user can review it separately.

**For the `git` kind only**, run the one-time init before any other verb:

```bash
bash "$SKILL_DIR/adapters/git.sh" init <name> <CLONE_URL>
```

### 3a. Tarball fallback (adapter-less upstreams)

Some formulae ship only release tarballs with no git host any adapter understands — SourceForge is
the common case (real case: `lame`, `homepage: lame.sourceforge.io`). Diff the two release tarballs
directly. This substitutes for steps 4 and 6.

```bash
D=/tmp/brew-tarball-<name>; mkdir -p "$D-old" "$D-new"
# 1. Fetch both. brew's stable_url is the LATEST; derive the installed URL by substituting
#    the version into the same path (SourceForge keeps every version).
curl -sSL -o "$D-new.tgz" "<latest stable_url>"
curl -sSL -o "$D-old.tgz" "<installed-version url>"
# 2. Reject HTML error pages masquerading as tarballs (a 404/redirect saved as .tgz):
file "$D-new.tgz" "$D-old.tgz"   # must say "gzip/xz/bzip2 compressed data", NOT "HTML"
# 3. INTEGRITY ANCHOR — verify the latest tarball against Homebrew's pinned checksum.
#    A mismatch means you are NOT reviewing what brew will install: STOP and flag it.
brew info --json=v2 <name> | jq -r '.formulae[0].urls.stable.checksum'
shasum -a 256 "$D-new.tgz"
```

If the SHA matches, extract both and compare the trees:

```bash
# --strip-components=1 drops the version-named top dir (lame-4.0/, lame-3.100/) so both trees
# share relative paths. Without it EVERY path differs by its top segment and the whole tree
# reads as "added".
tar xf "$D-old.tgz" -C "$D-old" --strip-components=1
tar xf "$D-new.tgz" -C "$D-new" --strip-components=1
comm -13 <(cd "$D-old" && find . -type f | sort) <(cd "$D-new" && find . -type f | sort)
diff -rq "$D-old" "$D-new"
```

Run the **same step-6 heuristic scan** over the added/changed files. There is no per-commit author
cross-check with tarballs, so concentrate the HIGH/MEDIUM patterns on: build scripts
(`configure.ac`, `Makefile.am`, `*.m4`, `*.sh`) for injected `curl|wget → shell` or `eval` of
network data; non-source-language additions (a C project sprouting `.py`/`.js` build glue); binary
blobs; and any network endpoint or long base64/hex blob a library of this kind should never carry.
For the **age gate**, use the tarball's release date (internal mtime from `file`, or the host's
listing).

A matching SHA + clean tree promotes to **UPDATE** (subject to the age gate); anything unexplained
downgrades exactly as in step 6. Note in the summary that the review was **tarball-based (no commit
history)**, and flag major-version jumps (`lame` 3.100 → 4.0) as behaviorally significant even when
supply-chain-clean.

### 4. Resolve tag names and release date

```bash
bash "$SKILL_DIR/adapters/<kind>.sh" resolve-tag <key...> "<VERSION>"
# → {"name": "v1.2.3", "sha": "...", "date": "2026-04-15T..."}   or {} if nothing matched
```

Call once for the installed version (`installed_versions[0]` — pin explicitly; `brew` allows
multiple installed versions for versioned formulae like `python@3.10`) and once for the latest.

Matching is a substring `contains("<VERSION>")`, which fails in four distinct ways. **Do not accept
either result at face value:**

1. **A tag came back with a suffix** (`vfox-v2026.9.1` for `2026.9.1`) — a variant shadowed the real
   tag; re-pick the exact match by hand.
2. **`{}` from a repo that plainly exists** — separator mismatch: curl tags `8.22.0` as
   `curl-8_22_0`. Retry with `.` replaced by `_` and by `-`. Fixing this re-exposes trap 1.
3. **`{}` still, after re-spelling** — the tag may be beyond the adapter's single tag page. Re-run
   the lookup with `--paginate`; `mozilla/nss` is the standing case. A tag only the paginated
   lookup can see means the adapter cannot drive this formula: MANUAL, and name the tag.
4. **`{}` for the base version only** — substitute the nearest lower tag as a conservative superset;
   do not jump to MANUAL.

All four, with the commands: `references/adapters.md`, "Tag-resolution traps". If the **latest** tag
will not resolve, record MANUAL with reason "tag '<version>' not found" and skip step 6.

Compute age in days:

```bash
now=$(date +%s)
epoch=$(gdate -d "<date from resolve-tag>" +%s)   # gdate handles Z and ±HH:MM; jq's fromdate does not
age_days=$(( (now - epoch) / 86400 ))
```

Without `gdate`, use the BSD `date` normalisation in `references/adapters.md`.

### 4a. Advisory-ID scan (every candidate, WAIT included)

Before classifying, check whether the release *itself* says it fixes a published advisory.

**Three sources. Run all three — their coverage is disjoint.** On 2026-09-03 three of the four
formulae that mattered were found by exactly one source each.

#### Source A — GitHub Repository Security Advisories (`github` kind only)

The maintainer's own record, and the only source carrying **severity and CVSS**.

```bash
gh api "repos/<owner>/<repo>/security-advisories?per_page=100" --paginate \
  | jq -r --arg v "<NEW_VERSION>" \
      '[.[] | select([.vulnerabilities[]?.patched_versions // ""] | any(contains($v)))]
       | .[] | "\(.ghsa_id) \(.severity) cvss=\(.cvss.score // "?") cve=\(.cve_id // "none") \(.summary)"'
```

Filter on `patched_versions` containing the **new** version — that is what makes a hit mean *this
upgrade fixes it*. `.cvss.score` is null on a minority of advisories; report those as `CVSS n/a` and
rank on `.severity`, which is always populated. An empty result is not an all-clear — fall through.

#### Source B — OSV.dev, `GIT` ecosystem

Covers projects that publish CVEs with git ranges but file no GitHub advisories. OpenSSL is the case
in point: A returns **zero** for `openssl/openssl`, B returns exactly the eleven CVEs 3.6.4 fixes.

```bash
curl -s --max-time 25 -X POST https://api.osv.dev/v1/query -H 'Content-Type: application/json' \
  -d '{"package":{"name":"https://github.com/<owner>/<repo>","ecosystem":"GIT"},"version":"<INSTALLED_VERSION>"}' \
  | jq -r '.vulns[]? | select(.id | startswith("OSV-") | not) | "\(.id) \(.summary)"'
```

Query the **installed** version — OSV answers "what affects this version", so a hit means what you
have is vulnerable. `name` is the repo's canonical web URL, not necessarily GitHub; OSV's GIT
coverage off GitHub is thin, so an empty result there is weak evidence. Drop `OSV-`-prefixed ids:
those are OSS-Fuzz crash reports, not advisories (libheif alone carries 16).

#### Source C — the two greps over the diff

The only source that works when a project files nothing anywhere. It needs the diff, so fetch now.

Run `fetch-diff` for every formula whose base and latest tags resolved — including ones that failed
the age gate, and including a substituted base. This writes the `$OUT.patch` / `$OUT-meta.json`
artefacts step 6 also consumes, so **do not fetch twice**. A non-zero adapter exit is handled by the
exit-code table in `references/adapters.md` — read it rather than assuming: **bitbucket exit 3 with
an empty `$OUT.patch` still leaves a usable `$OUT-meta.json`**, which is enough for a MEDIUM-only
scan and must not be dropped to MANUAL. Where the table does leave the formula with nothing, it gets
no advisory scan at all: classify **MANUAL**, and never let a failed fetch read as a clean scan.

**Check every fetched diff for truncation before scanning it.** A truncated diff greps exactly like
a complete clean one.

```bash
jq -r 'if (.ahead == null) then "UNKNOWN: non-github meta — see references/adapters.md"
       elif (.ahead > (.commits|length)) or ((.files|length) >= 300)
       then "TRUNCATED: \(.commits|length)/\(.ahead) commits, \(.files|length) files"
       else "complete: \(.ahead) commits, \(.files|length) files" end' "$OUT-meta.json"
```

The `.ahead == null` arm is load-bearing: only `github.sh` emits `ahead`, and jq treats `null > 3`
as false, so a two-arm form prints `complete: null commits` for every non-GitHub formula — a
fabricated all-clear. Per-kind caps (bitbucket truncates undetectably) are in
`references/adapters.md`. **A truncated diff makes the scan inconclusive, not clean.**

**Run both greps. Neither is a superset of the other.**

```bash
OUT=/tmp/brew-diff-<name>
ADV='CVE-[0-9]{4}-[0-9]{4,}|GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}'

# A. Commit subjects — high precision. Maintainers cite the advisory in the fix's subject line.
jq -r '.commits[].message' "$OUT-meta.json" | grep -oEi "$ADV" | sort -u

# B. Added patch lines — high recall. Catches projects that record advisories in an in-tree
#    changelog (NEWS, Misc/NEWS.d) and never in a commit subject. Needs triage.
grep -nE "^\+.*($ADV)" "$OUT.patch"
```

**Triage the B hits by reading the matched line** — that is what `grep -n` prints them for, and at
these volumes it costs seconds. Discard hits in translation catalogues (`*.po`) and other generated
artefacts, and hits in historical or archived release notes: a fix cites its *own* advisory, so an
ID attached to a version far below the one under review is documentation, not a fix. Keep hits
sitting in the entry for the version being installed — glib's `NEWS` line
`- #3985 (CVE-2026-15588) Security report: GDBusServer pre-authentication DoS` is the shape to
expect.

**Where A returns hits, prefer its list over C's.** C reads commit subjects and patch text, which
mention *previously* fixed advisories in comments and regression-test names; on libheif it counted
13 where the truth was 11. Reconcile rather than reporting a union.

A surviving hit means the release fixes a known, *published* vulnerability. Record the IDs — they
drive the top row of the step-5 table and appear in the summary.

**A miss is not an all-clear.** Plenty of genuine fixes ship with no ID. `fontconfig` 2.18.3 fixed a
NULL-pointer dereference and a use-after-free with no CVE, no grype match, and nothing on either
grep. Those stay under the age gate, but say so in the summary so the user can override deliberately.

### 5. Classify

Apply rules in order:

| Condition | Classification | Rationale |
|---|---|---|
| Release cites a published advisory (surviving step 4a hit) | **SECURITY** | Maintainer-attested fix for a known vuln. Age gate does not apply. Outranks grype, which routinely misses exactly these. |
| Name appears in grype CVE map | **SECURITY** | Known vuln — age gate does not apply. Cross-check against the step-4a IDs: a grype hit with an empty `fix` array and no 4a corroboration is usually a stale false positive, so report it as such rather than as the reason to upgrade. |
| Diff truncated (step 4a) **and** age ≥ 10 days | **REVIEW MANUALLY** | The scan saw a sample, not the release; a clean grep proves nothing about the other 23,000 commits. Never let this become a plain UPDATE. |
| Latest tag age ≥ 10 days | **UPDATE** (diff-pending) | Passes age gate, proceed to diff review. |
| Latest tag age < 10 days | **WAIT** | Too fresh — let it bake. Step 4a already cleared it of *published* advisories; no full diff review. |
| Upstream or tag not resolvable | **MANUAL** | Cannot inspect — user decides. |

A truncated diff on a **WAIT** formula stays WAIT — it is not being upgraded — but the summary must
still mark it, because re-running after the gate expires truncates identically and will not resolve
itself. A surviving 4a hit or a grype match still promotes to **SECURITY** regardless of truncation;
say in the summary that the review was partial.

**MANUAL** has nothing to diff and skips step 6. Everything else already has its artefacts from
step 4a: run the full heuristic scan for **SECURITY**, **UPDATE**, and **REVIEW MANUALLY**. For
**WAIT**, the step-4a advisory grep is the whole review.

**A truncation-derived REVIEW MANUALLY still gets the step-6 scan.** It is the one REVIEW MANUALLY
that arrives with artefacts already on disk rather than as a step-6 verdict, so it is easy to route
to the same "nothing to diff" path as MANUAL — do not. A HIGH finding inside the sample is a real
HIGH finding and promotes to **DO NOT UPGRADE**; only the *absence* of findings is what truncation
makes meaningless.

### 6. Diff review (SECURITY, UPDATE, and REVIEW MANUALLY)

Step 4a already ran `fetch-diff`, so the artefacts exist on disk — reuse them rather than fetching
again.

```bash
OUT=/tmp/brew-diff-<name>
# $OUT.patch      — raw unified diff (input to the HIGH grep)
# $OUT-meta.json  — {commits, files} (input to the MEDIUM heuristics)
```

Adapter exit codes and their handling: `references/adapters.md`.

Apply the same patterns to every kind by grepping `$OUT.patch` and reading `$OUT-meta.json`. Only
`^+` lines (additions) count; never alert on removals. The **author cross-check** is GitHub-only
(`gh api repos/<owner>/<repo>/commits?author=<login>&per_page=5`); for gitlab/bitbucket/git, skip it
and note "author cross-check unavailable" in the summary.

**HIGH severity (flag as DO NOT UPGRADE):**
- New `curl`, `wget`, `Invoke-WebRequest` piped into a shell (`| bash`, `| sh`, `| powershell`)
- New dynamic execution primitives applied to anything attacker-controllable — `eval`, `exec`,
  shell-invoking process runners (`system`, `popen`, Python's `subprocess` with `shell=True`, Ruby
  backticks), Lua `loadstring`/`assert(loadstring(...))`, `vim.fn.system`
- Reads of credential-bearing paths: `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.netrc`, `.env`,
  `*_token*`, `*_key*`, shell history files
- Large inline base64 / hex / long numeric blobs (>200 chars, suggestive of obfuscated payload)
- Network endpoints to domains not obviously associated with the project
- Commits by an author who does not appear elsewhere in the repo's recent history

**MEDIUM severity (flag as REVIEW MANUALLY):**
- Unexpectedly large addition of unrelated files (>20 new files in a non-refactor release)
- Binary file additions
- New runtime dependencies in build files (`package.json`, `Cargo.toml`, `go.mod`, configure scripts)
- Significant non-source-language file additions (a pure-C project suddenly gaining `.py` build glue)

**LOW / clean:** README / docs only; syntax, type or doc-comment fixes; test additions; refactors
within existing files.

Downgrade **UPDATE** to **REVIEW MANUALLY** on MEDIUM findings, to **DO NOT UPGRADE** on HIGH. For
**SECURITY**, keep the classification but surface HIGH findings prominently — the user still needs
to know.

### 7. Chat summary

Print one compact block, grouped by classification:

```
Processed N formula(s):

SECURITY (upgrade recommended regardless of age):
  <name> <old> → <new>  Advisories: <IDs>  Max severity: <critical|high|medium|low> (CVSS <x.y|n/a>)
                        Source: <A github | B osv | C grep | grype, combined>  Diff: <clean | N flags>

UPDATE (≥10d old, diff clean):
  <name> <old> → <new>  Age: <X>d  Diff: clean

REVIEW MANUALLY:
  <name> <old> → <new>  Reason: <MEDIUM finding summary>
  <name> <old> → <new>  Reason: diff truncated <N>/<AHEAD> commits, <F> files — sampled only,
                        clean grep proves nothing; sampled scan: <clean | N flags>

WAIT (<10d old):
  <name> <old> → <new>  Age: <X>d — try again in <10-X>d
  <name> <old> → <new>  Age: <X>d — ⚠ security-relevant, no advisory ID: <one line>
  <name> <old> → <new>  Age: <X>d — ⚠ diff truncated <N>/<AHEAD> commits — scan inconclusive

DO NOT UPGRADE:
  <name> <old> → <new>  Reason: <HIGH finding summary>

MANUAL (upstream diff unavailable):
  <name>  Reason: <upstream not resolvable | tag not found | tag beyond adapter's first tag page | upstream unreachable>

Casks (not analyzed):
  <name1>, <name2>, ...

---
Upgrade command (SECURITY + UPDATE only):
  brew upgrade <name1> <name2> <name3>
```

Omit empty sections. If there are no approved upgrades, omit the final command block entirely and
say so explicitly.

### 8. Persist the report

Save the summary as Markdown to `$HOME/dotfiles/.local/brew-review-$(date +%F).md`. Run
`mkdir -p "$HOME/dotfiles/.local"` first — the directory does not exist on a fresh checkout.

Format the file as proper Markdown (tables per classification, fenced code block for the upgrade
command) rather than the compact monospace block printed to chat. Write it even when there are no
approved upgrades, so the user can see what was deferred and why. Overwrite a same-day file — the
latest run is canonical.
