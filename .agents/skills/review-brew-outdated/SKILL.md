---
name: review-brew-outdated
description: Review Homebrew formulae reported by `brew outdated`, classify each update by security impact and release age, analyze the upstream diff for supply-chain red flags, and print a chat summary with a ready-to-paste `brew upgrade` command covering only the approved packages. Triggered by requests like "review brew outdated", "triage homebrew updates", "check if brew packages are safe to upgrade", or explicit /review-brew-outdated invocation.
---

# review-brew-outdated

Reviews outdated Homebrew formulae and decides which are safe to upgrade. For each candidate it:

1. Cross-references installed versions against a CVE scan (syft + grype) to flag security-relevant updates.
2. Greps every candidate's own commit subjects *and* in-tree changelog additions for published advisory IDs (CVE / GHSA), because grype systematically misses fresh fixes in Homebrew C/C++ libraries. A hit outranks the age gate.
3. Enforces a 10-day release-age gate for non-security updates (same policy as Renovate).
4. Scans the upstream diff for supply-chain red flags (remote script exec, credential access, obfuscation, unexpected dependency pulls). Host-aware: GitHub, GitLab, Bitbucket Cloud, and generic git (cgit / self-hosted) are all supported via per-kind adapters.
5. Prints a chat summary and a `brew upgrade` command covering only packages classified as UPDATE.

The skill never runs `brew upgrade` itself — the user runs the printed command.

## Scope

- Formulae only. Casks are listed as "manual review" in the summary but not analyzed.
- Optional package arguments: `/review-brew-outdated jq git` restricts processing to the named formulae. No arguments processes every outdated formula.
- Safe to re-run — per-run artefacts under `/tmp/brew-*.{json,patch}` are overwritten each time. The `git` adapter's bare-clone cache at `/tmp/brew-review-cache/` persists across invocations for speed (re-runs just `git fetch` instead of re-cloning) and is safe to delete between runs.

## Required tools

`brew`, `gh` (authed), `jq`, `syft`, `grype`, `curl`, `git`. Step 4a additionally queries
`api.osv.dev` over plain `curl` — no account, no token. All are installed via aqua (`anchore/syft`, `anchore/grype`) or available by default on the system.

"authed" needs care for `gh` specifically: the adapters run as **child processes**, which inherit neither shell aliases nor functions. Where `gh` is authenticated through a 1Password shell plugin (an alias/function in `~/.config/op/plugins.sh`), that wrapper does not reach them. `adapters/github.sh` handles this itself — it falls back to `op plugin run -- gh` when `gh` cannot authenticate on its own — so nothing needs doing per-run. But if you ever lift a `gh` call out of the adapter into a standalone script, it will hit the same wall. The `gh api` calls this doc runs inline (the author cross-check in step 6) are fine: they execute in the top-level shell, where the wrapper is defined.

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

**Record the DB the scan actually used — from the scan's own output, never from a concurrent
`grype db status`.** grype auto-updates its DB when a scan starts (the default; no
`GRYPE_DB_AUTO_UPDATE` is set here) and `syft` takes minutes to build the SBOM first, so a
`grype db status` run alongside the scan reads the *previous* cache and reports a staleness that
no longer applies by the time grype runs. Measured 2026-09-03: `grype db status` reported
`built 2026-08-27` / `Status: invalid` while the scan it was racing recorded
`built 2026-09-03T06:30:55Z` / `valid: true`.

```bash
jq -c '.descriptor.db.status | {built, valid}' /tmp/brew-cves.json
```

That field is written by the scan itself, so it cannot race. Report *that* value as the DB age.

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

**Homepages that name no repository.** Several formulae publish only tarballs from a
project-owned host, so no row above matches and they fall to MANUAL despite having a perfectly
reviewable upstream. Check this list before giving up — knowing the mirror is enough to make most
of them ordinary `github` kind, with `nss` the noted exception:

| Homepage / stable_url host | Key |
|---|---|
| `gnupg.org`, `www.gnupg.org` | `gpg/<formula>` — `gpg/gnupg`, `gpg/gpgme`, `gpg/libgcrypt`. **`gpgmepp` is its own repo `gpg/gpgmepp`**, not a subdirectory of `gpg/gpgme`, and its tags (`gpgmepp-2.2.0`) track a cadence separate from gpgme's. |
| `ftp.mozilla.org/pub/security/nss`, `firefox-source-docs.mozilla.org` | `mozilla/nss` (`nss-dev/nss` redirects here) — **the adapter cannot resolve this one**; see the pagination note in step 4. Tags are `NSS_3_128_RTM`: underscores plus an `_RTM` suffix, so the separator-mismatch guard applies as well. |

Do **not** spend probes on `git.gnupg.org` or `dev.gnupg.org`: both refused `git ls-remote` for
gnupg, gpgme, libgcrypt and gpgmepp on 2026-09-03. The GitHub mirror is the only working path.

If none match, try the **tarball fallback** (§3a) before giving up; only if that is not applicable, record as **MANUAL** with reason "upstream not resolvable" and skip steps 4–6.

**Brew-revision-only bumps** (`8.1` → `8.1_1`, `1.86.0` → `1.86.0_1`): the upstream version is unchanged — only the Homebrew formula revision number bumped. Both versions resolve to the same upstream tag and `compare` returns an empty diff. Record these as UPDATE with reason "brew revision only, no upstream diff" and skip the heuristic scan. Do NOT classify as MANUAL. A revision bump commonly means a rebuild against a newer dependency; if the revision bump log message cites another formula (e.g. "revision bump for x265 4.2"), note the dependency in the summary so the user can review it separately.

**For the `git` kind only**, run the init step once per formula before resolve-tag or fetch-diff. This clones the bare repo into `${XDG_CACHE_HOME:-$HOME/.cache}/brew-review/<name>.git/` (reused on subsequent runs, with stale/invalid caches auto-removed before re-cloning):

```bash
bash "$SKILL_DIR/adapters/git.sh" init <name> <CLONE_URL>
```

Throughout the rest of this doc, `$SKILL_DIR` is this skill's directory: `$HOME/dotfiles/.agents/skills/review-brew-outdated`. The `skills` directory under `.claude/` is a symlink pointing here, so a path through there reaches the same files. Adapters live under `$SKILL_DIR/adapters/<kind>.sh` and share a uniform calling convention — see steps 4 and 6.

### 3a. Tarball fallback (adapter-less upstreams)

Some formulae ship only release tarballs with no git host any adapter understands — SourceForge is the common case (real case: `lame`, `homepage: lame.sourceforge.io`, `stable_url: downloads.sourceforge.net/…`). Rather than dropping these straight to MANUAL, diff the two release tarballs directly. This substitutes for steps 4 and 6.

```bash
D=/tmp/brew-tarball-<name>; mkdir -p "$D-old" "$D-new"
# 1. Fetch both tarballs. brew's stable_url is the LATEST; derive the installed URL by
#    substituting the version into the same path (SourceForge keeps every version).
curl -sSL -o "$D-new.tgz" "<latest stable_url>"
curl -sSL -o "$D-old.tgz" "<installed-version url>"
# 2. Reject HTML error pages masquerading as tarballs (a 404/redirect saved as .tgz):
file "$D-new.tgz" "$D-old.tgz"   # must say "gzip/xz/bzip2 compressed data", NOT "HTML"
# 3. INTEGRITY ANCHOR — verify the latest tarball against Homebrew's pinned checksum.
#    A mismatch means you are NOT reviewing what brew will install: STOP and flag it.
brew info --json=v2 <name> | jq -r '.formulae[0].urls.stable.checksum'
shasum -a 256 "$D-new.tgz"
```

If the SHA matches Homebrew's pin, extract both and compare the trees:

```bash
# --strip-components=1 drops the version-named top dir (lame-4.0/, lame-3.100/) so both
# trees share the same relative paths. Without it EVERY path differs by its top segment
# and the comparison is worthless — the whole tree reads as "added".
tar xf "$D-old.tgz" -C "$D-old" --strip-components=1
tar xf "$D-new.tgz" -C "$D-new" --strip-components=1
# added files (in new, not old):
comm -13 <(cd "$D-old" && find . -type f | sort) <(cd "$D-new" && find . -type f | sort)
# changed/removed overview:
diff -rq "$D-old" "$D-new"
```

Then run the **same step-6 heuristic scan** over the added/changed files. There is no per-commit author cross-check with tarballs, so concentrate the HIGH/MEDIUM patterns on: build scripts (`configure.ac`, `Makefile.am`, `*.m4`, `*.sh`) for injected `curl|wget → shell` or `eval` of network data; non-source-language additions (a C project sprouting `.py`/`.js` build glue); binary-blob additions; and any network endpoint or long base64/hex blob a library of this kind should never carry. For the **age gate**, use the tarball's release date — the internal mtime from `file` output, or the date shown on the host's file listing.

A matching SHA + clean tree promotes the formula to **UPDATE** (subject to the age gate); anything unexplained downgrades exactly as in step 6. Note in the summary that the review was **tarball-based (no commit history)**, and flag major-version jumps (e.g. `lame` 3.100 → 4.0) as behaviorally significant for the user even when supply-chain-clean.

### 4. Resolve tag names and release date

Every adapter exposes the same `resolve-tag` verb with uniform JSON output:

```bash
bash "$SKILL_DIR/adapters/<kind>.sh" resolve-tag <key...> "<VERSION>"
# → {"name": "v1.2.3", "sha": "...", "date": "2026-04-15T..."}
# → {} if no tag contains the version string
```

Adapters apply a `contains("<VERSION>")` match against upstream tag listings — tag naming is not standardised (Homebrew's `1.6.58` may appear as `v1.6.58`, `libpng-1.6.58`, `release-1.6.58`, etc.), so substring match is the lowest-common-denominator that works across all hosts.

> **`git` kind is the exception to the uniform `<key...>` convention.** Its `resolve-tag` takes only `<name> <version>` — the clone URL is **not** passed here (it is used solely by the one-time `init` in step 3). Likewise git's `fetch-diff` is `<name> <old_ref> <new_ref> <out_prefix>`, with no URL. Passing the clone URL into `resolve-tag`/`fetch-diff` shoves the version into the wrong slot, so every tag silently resolves to `{}`. github/gitlab/bitbucket instead carry their full key (`<owner/repo>`, `<host> <project>`, `<workspace> <repo>`) into every verb.

**Guard against variant-tag shadowing.** Because the match is a substring, a suffixed variant can outrank the plain release tag — e.g. `contains("4.1.0")` may return `v4.1.0-cqp-extended` (an experimental/fork tag) instead of `v4.1.0`, silently corrupting the diff base. This bites hardest on the OLD/base ref, where a wrong tag inflates the diff with unrelated changes. When more than one tag matches, prefer the tag that is *exactly* the expected version (`v<VERSION>` / `<VERSION>` / `<name>-<VERSION>`) over any longer suffixed sibling; if the adapter handed back a suffixed variant, re-list the tags and pick the exact match by hand before calling `fetch-diff`. Confirmed live on 2026-09-03: `mise` 2026.9.1 resolved to **`vfox-v2026.9.1`** instead of `v2026.9.1`.

**Guard against separator mismatch, too — this one returns `{}`, not a wrong tag.** The substring
match assumes upstream spells the version the way Homebrew does. Plenty of projects do not: curl
tags `8.22.0` as `curl-8_22_0`, so `contains("8.22.0")` misses *both* refs and the formula reads as
"tag not found" → MANUAL, even though the repo resolved fine and the tags are right there. Before
accepting `{}` from a repo that plainly exists, retry with `.` replaced by `_` (and by `-`), or
just list the tags and pick by eye:

```bash
gh api "repos/<owner>/<repo>/tags?per_page=100" --paginate -q '.[].name' \
  | grep -F "$(echo '<VERSION>' | tr . _)"
```

`{}` means "no tag *contained that exact string*", which is not the same as "no tag for this
release".

**The two guards are one procedure, not two — fixing the separator re-exposes the shadowing trap.**
Confirmed on curl 8.22.0: once `8_22_0` matches, the tag list leads with `rc-8_22_0-3`,
`rc-8_22_0-2`, `rc-8_22_0-1` and only *then* `curl-8_22_0`. Taking `.[0]` at that point pins a
release candidate. Always re-apply the exact-match preference above after re-spelling the version.

**`--paginate` is load-bearing, and the adapter does not have it.** `github.sh resolve-tag` issues a
single `tags?per_page=100`, and GitHub does not return that page in any useful order — for a repo
with many tags the newest release may simply not be on it. `nss` is the standing case: page 1 is
2000s-era refs (`travisWebshell_03082000_BASE`, `nss_20021204`, …) with **no `NSS_3_*` tag at all**,
so the adapter returns `{}` for `mozilla/nss` no matter how the version is spelled, and the
separator guard cannot save it. Measured 2026-09-04: the paginated command above finds
`NSS_3_128_RTM` and `NSS_3_128_BETA1`; without `--paginate` it exits 1 with no output.

So for `nss` — and any formula where the paginated lookup finds a tag the adapter did not —
classify **MANUAL** with reason "tag beyond adapter's first tag page", and note the tag you found by
hand so the user can review the release themselves. Do not hand a tag the adapter never produced to
`fetch-diff` and report the result as an adapter-verified diff.

Call once for the installed version (`installed_versions[0]` — pin explicitly; the array normally has one entry but `brew` allows multiple installed versions for versioned formulae like `python@3.10`) and once for the latest version.

- If the **latest** version resolves to `{}`, record the formula as **MANUAL** with reason "tag '<version>' not found" and skip step 6 — there is nothing to diff *to*.
- If only the **installed/base** version resolves to `{}` (latest is fine), do **not** jump straight to MANUAL. Some upstreams skip or never tag an intermediate release (real case: `libmicrohttpd` 1.0.5 has no tag on the git.gnunet.org mirror, which jumps `v1.0.4 → v1.0.6`). List the tags, pick the **nearest lower** tag as the base, and diff that → latest as a **conservative superset** — it reviews *more* than the user's actual upgrade span, never less. Note the substituted base in the summary (e.g. "base v1.0.5 absent — reviewed v1.0.4→v1.0.6"). This mirrors the lazy-lock skill's intermediate-commit fallback. Fall back to MANUAL only if no usable lower tag exists.

Compute age in days from the `date` field. **The `date` value is not always UTC-`Z`:** GitHub returns `…Z`, but the `gitlab` and `git` kinds return an ISO-8601 timestamp with a numeric offset (`2026-07-14T08:39:09+02:00`, `…-05:00`). jq's `fromdate` only parses the `Z` form and aborts with `date "…" does not match format "%Y-%m-%dT%H:%M:%SZ"` on offset timestamps — so parse with an offset-aware tool instead:

```bash
now=$(date +%s)
# gdate (GNU coreutils, installed via brew) handles both the Z form and ±HH:MM offsets:
epoch=$(gdate -d "<date from resolve-tag>" +%s)
# Fallback if gdate is unavailable — BSD `date` needs Z→+0000, fractional seconds dropped
# (gitlab emits .000), and the offset colon stripped before %z will parse it:
#   d="<date>"; norm=$(echo "${d/Z/+0000}" | sed -E 's/\.[0-9]+//; s/([+-][0-9][0-9]):([0-9][0-9])$/\1\2/'); epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$norm" +%s)
age_days=$(( (now - epoch) / 86400 ))
```

### 4a. Advisory-ID scan (every candidate, WAIT included)

grype alone is not a sufficient security signal for this repo, and both of its failure
modes point the wrong way (see **Why these choices**). Before classifying, check whether
the release *itself* says it fixes a published advisory.

**Three sources, in this order. Run all three — their coverage is disjoint.** On 2026-09-03 three
of the four formulae that mattered were found by exactly one source each, and the sources
disagreed about the fourth.

#### Source A — GitHub Repository Security Advisories (`github` kind only)

The maintainer's own advisory record, and the only source here that carries **severity and CVSS** —
no amount of commit-message reading will give you that.

```bash
gh api "repos/<owner>/<repo>/security-advisories?per_page=100" --paginate \
  | jq -r --arg v "<NEW_VERSION>" \
      '[.[] | select([.vulnerabilities[]?.patched_versions // ""] | any(contains($v)))]
       | .[] | "\(.ghsa_id) \(.severity) cvss=\(.cvss.score // "?") cve=\(.cve_id // "none") \(.summary)"'
```

Filter on `patched_versions` containing the **new** version — that is what makes a hit mean *this
upgrade fixes it*. An empty result is not an all-clear: fall through to B.

`.cvss.score` is null on a minority of advisories (2 of libheif's 11 on 2026-09-03), which is why
the `// "?"` is there. Report those as `CVSS n/a` rather than dropping them or reading the missing
score as low — `.severity` is populated even when the score is not, so rank on that.

#### Source B — OSV.dev, `GIT` ecosystem (any kind, once you know the repo URL)

Covers projects that publish CVEs with git ranges but file no GitHub advisories. OpenSSL is the
case in point: Source A returns **zero** for `openssl/openssl` because OpenSSL publishes on
`openssl-library.org` instead, while Source B returns exactly the eleven CVEs 3.6.4 fixes.

```bash
curl -s --max-time 25 -X POST https://api.osv.dev/v1/query -H 'Content-Type: application/json' \
  -d '{"package":{"name":"https://github.com/<owner>/<repo>","ecosystem":"GIT"},"version":"<INSTALLED_VERSION>"}' \
  | jq -r '.vulns[]? | select(.id | startswith("OSV-") | not) | "\(.id) \(.summary)"'
```

The `name` is the repository's canonical web URL, not necessarily a GitHub one — use
`https://gitlab.com/<project>` or the clone URL minus `.git` for `gitlab` / `bitbucket` / `git`
kinds. OSV's GIT coverage outside GitHub is thin, so an empty result there is even weaker evidence
than usual.

Query the **installed** version here — OSV answers "what affects this version", so a hit means what
you have is vulnerable. Drop `OSV-`-prefixed ids: those are OSS-Fuzz crash reports, not published
advisories, and libheif alone carries 16.

#### Source C — the two greps over the diff

The third net, and the only one that works when a project files nothing anywhere. It needs the
diff, so fetch it now.

Run `fetch-diff` now for every formula whose base and latest tags resolved — including ones
that failed the age gate, and including the substituted base of step 4. This writes the same
`$OUT.patch` / `$OUT-meta.json` artefacts step 6 consumes, so **do not fetch twice**; step 6
reuses them. A non-zero adapter exit is handled exactly as in step 6 (see the exit-code table
there), except that a formula whose fetch fails gets no advisory scan at all — classify it
**MANUAL**, never let a failed fetch read as a clean scan.

**Check every fetched diff for truncation before you scan it.** Compare endpoints cap their
response, and say so nowhere in the text you grep — a truncated diff greps exactly like a complete
clean one, so an unchecked truncation reads as an all-clear.

For **`github` kind only**, the cap is **250 commits and 300 files**, and `github.sh` records the
real span in `.ahead`, which is what makes this detectable at all:

```bash
jq -r 'if (.ahead == null) then "UNKNOWN: non-github meta, .ahead absent — see below"
       elif (.ahead > (.commits|length)) or ((.files|length) >= 300)
       then "TRUNCATED: \(.commits|length)/\(.ahead) commits, \(.files|length) files"
       else "complete: \(.ahead) commits, \(.files|length) files" end' "$OUT-meta.json"
```

**The `.ahead == null` arm is not decoration — without it this check lies.** Only `github.sh` emits
`ahead`; `gitlab.sh`, `bitbucket.sh` and `git.sh` write `{commits, files}` only. jq evaluates
`null > 3` as `false`, so the naive two-arm form falls to the else branch and prints
`complete: null commits, N files` for every non-GitHub formula — a fabricated all-clear, which is
precisely the failure this paragraph exists to prevent.

What the other three actually do:

| kind | cap | detectable? |
|---|---|---|
| `github` | 250 commits / 300 files | **yes** — via `.ahead`, above |
| `bitbucket` | 100 commits (`pagelen=100`), 200 files (`pagelen=200`), neither paginated | **no** — no total is fetched. Treat a diff at exactly 100 commits or 200 files as truncated. |
| `gitlab` | server-side compare limit, instance-dependent | **no** — treat a suspiciously round or huge span as unverified |
| `git` | none — local clone, full history | n/a, always complete |

A truncated diff makes the step-4a scan **inconclusive, not clean.** Classify per step 5 and say so
in the summary — never let a sampled diff be reported as reviewed. Measured 2026-09-03: `libomp`
22.1.8→23.1.0 was **23,416** commits behind a 250-commit sample, `mise` 2,444, `usage` 622, `curl`
525; `nss` (resolved by hand — see step 4) had all 52 commits but hit the 300-file cap. Every one of
them greped clean.

**Run both greps. Neither is a superset of the other.**

```bash
OUT=/tmp/brew-diff-<name>
ADV='CVE-[0-9]{4}-[0-9]{4,}|GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}'

# A. Commit subjects — high precision. Maintainers cite the advisory in the fix's subject line.
jq -r '.commits[].message' "$OUT-meta.json" | grep -oEi "$ADV" | sort -u

# B. Added patch lines — high recall. Catches projects that record advisories in an in-tree
#    changelog (NEWS, Misc/NEWS.d) and never in a commit subject. Needs triage; see below.
grep -nE "^\+.*($ADV)" "$OUT.patch"
```

**Measured 2026-09-03 — why all three, and which to trust when they disagree:**

| Formula | A (GitHub) | B (OSV GIT) | C (greps) | grype |
|---|---|---|---|---|
| `libheif` 1.23.2→1.23.3 | **11**, one *critical* CVSS 9.8 | 0 | 13 — three wrong, one missed | 0 |
| `pcre2` 10.47→10.48 | **6**, no noise | 0 | 6, after triaging 13 historical IDs | 0 |
| `libde265` 1.1.1→1.1.2 | **2** | 0 | 2 | 0 |
| `openssl@3` 3.6.3→3.6.4 | 0 | **11** | 11 | 0 |
| `gnupg`, `curl`, `nss`, `libgcrypt` | 0 | 0 | 0 | 1 stale |

**Where A returns hits, prefer its list over C's.** On libheif the greps counted 13 by reading code
comments about *older* fixes as current (`GHSA-jc8f-p23p-5hjg` was patched in v1.23.1,
`GHSA-2c3g-p585-8rpq` in 1.19.6, `GHSA-prcj-g5xh-rw95` is not an advisory at all) while
simultaneously dropping `GHSA-73p7-m7gg-w2jv` by misreading it as a prior incomplete fix. The
changelog-noise problem this section warns about applies to **code comments too**, and C cannot
tell you that `GHSA-x8r2-mggj-j6wr` is CVSS 9.8 while the other ten are not.

Do **not** reach for `osv-scanner` against the SBOM as a shortcut. Tested on the same
`/tmp/brew-sbom.json`: 39 vulnerable packages, **none of them an outdated formula** — every hit was
a Go/Rust/Python dependency vendored inside a bottle, which `brew upgrade` cannot act on. It shares
grype's purl gap and adds noise.

Measured over the 2026-08-28 formulae, source C alone:

| Formula | A: subjects | B: added patch lines |
|---|---|---|
| `imagemagick` 7.1.2-29 → -30 | **10 GHSAs** | 0 |
| `libheif` 1.23.1 → 1.23.2 | **8 GHSAs** | 6 (a subset of A) |
| `glib` 2.88.2 → 2.88.3 | 0 | **CVE-2026-15588** |
| `python@3.10` 3.10.20 → 3.10.21 | 2 | **8** (6 additional, all genuine) |
| `fontconfig`, `imath`, `little-cms2`, `sdl3`, `tmux` | 0 | 0 |

Running A alone would have missed glib's CVE-2026-15588 — the one advisory that run's grype
pass also missed, i.e. exactly the case this step exists to catch. Running B alone would have
missed all ten of imagemagick's GHSAs. When there is no commit list at all — a shallow
tag-to-tag diff, or the step-3a tarball path — B is the only signal available.

**Triage the B hits by reading the matched line.** That is what `grep -n` prints them for, and
at the volumes above (single digits per formula) it costs seconds. Discard:

- hits in translation catalogues (`*.po`) and other generated artefacts;
- hits in historical or archived release notes. A fix cites its *own* advisory, so an ID
  attached to a version far below the one under review is documentation, not a fix. A project
  migrating its changelog format (rst→md, per-release files → one combined file) re-adds years
  of old entries as new lines and can produce dozens of these at once.

Keep hits that sit in the entry for the version being installed. glib's `NEWS` line
`- #3985 (CVE-2026-15588) Security report: GDBusServer pre-authentication DoS` and CPython's
`Misc/NEWS.d` entries are the shape to expect.

A surviving hit means the release fixes a known, *published* vulnerability. Record the IDs —
they drive the top row of the step-5 table and appear in the summary.

**A miss is not an all-clear.** Plenty of genuine fixes ship with no ID at all. In the same run
`fontconfig` 2.18.3 fixed a NULL-pointer dereference and a use-after-free, with no CVE assigned,
no grype match, and nothing on either grep. Those stay under the age gate, but say so in the
summary so the user can override deliberately.

### 5. Classify

Apply rules in order:

| Condition | Classification | Rationale |
|---|---|---|
| Release cites a published advisory (surviving step 4a hit) | **SECURITY** | Maintainer-attested fix for a known vuln. Age gate does not apply. This outranks grype, which routinely misses exactly these. |
| Name appears in grype CVE map | **SECURITY** | Known vuln — age gate does not apply, upgrade is worth the tail risk. Cross-check against the step-4a IDs: a grype hit with an empty `fix` array and no 4a corroboration is usually a stale false positive, so report it as such rather than as the reason to upgrade. |
| Diff truncated at the API cap (step 4a) **and** age ≥ 10 days | **REVIEW MANUALLY** | The scan saw a sample, not the release; a clean grep proves nothing about the other 23,000 commits. Never let this become a plain UPDATE. |
| Latest tag age ≥ 10 days | **UPDATE** (diff-pending) | Passes age gate, proceed to diff review. |
| Latest tag age < 10 days | **WAIT** | Release is too fresh — let it bake. Step 4a already cleared it of *published* advisories; no full diff review. |
| Upstream or tag not resolvable | **MANUAL** | Cannot inspect — user decides. |

A truncated diff on a **WAIT** formula stays WAIT — it is not being upgraded — but the summary must
still mark it, because re-running after the gate expires will truncate identically and will not
resolve itself. A surviving 4a hit or a grype match still promotes to **SECURITY** regardless of
truncation; say in the summary that the review was partial.

**MANUAL** has nothing to diff and skips step 6. Everything else already has its
artefacts from step 4a: run the full heuristic scan for **SECURITY**, **UPDATE**, and
**REVIEW MANUALLY**. For **WAIT**, the step-4a advisory grep is the whole review — no full scan
needed.

**A truncation-derived REVIEW MANUALLY still gets the step-6 scan.** It is the one REVIEW MANUALLY
that arrives with artefacts already on disk rather than as a step-6 verdict, so it is easy to route
to the same "nothing to diff" path as MANUAL — do not. A HIGH finding inside the 250-commit sample
is a real HIGH finding and promotes the formula to **DO NOT UPGRADE**; only the *absence* of
findings is what the truncation makes meaningless.

### 6. Diff review (SECURITY, UPDATE, and REVIEW MANUALLY)

Step 4a already ran `fetch-diff` for every resolvable formula, so the artefacts below exist
on disk — reuse them rather than fetching again. The verb is documented here because this is
where its output is consumed. Every adapter exposes the same `fetch-diff`, writing two files
that share a common prefix:

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
  <name> <old> → <new>  Advisories: <IDs>  Max severity: <critical|high|medium|low> (CVSS <x.y>)
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

- **grype reports nothing for a formula that plainly fixed a vulnerability.** Expected, not a
  malfunction. Record the DB age from the scan's own `.descriptor.db.status` (step 2), never from a
  concurrent `grype db status`. And do not reach for `grype db update` as the remedy — a current DB
  does not close the gap: Homebrew C/C++ libraries have no purl→advisory mapping in the GitHub Advisory Database,
  so they match only once NVD assigns a CPE, which lags by weeks to months. Step 4a is the
  compensating control for both. Never read a grype miss as evidence of safety.
- **grype matches ancient CVEs with an empty `fix` array.** Also expected. Name-based CPE
  matching, plus Homebrew version strings it cannot parse (`7.1.2-29` is a patch counter, not
  a semver prerelease, and grype orders it *before* `7.1.2`), produce stale hits. Treat a grype
  hit as a prompt to read the release notes, never as the finding itself.
- **`grype db status` disagrees with the scan.** Not a fault — a race. grype auto-updates at scan
  start, `syft` runs for minutes beforehand, so a status check launched alongside the run reads the
  pre-update cache. On 2026-09-03 it reported a six-day-old `invalid` DB for a scan that recorded
  `valid: true` built that morning, and the whole "stale DB" finding had to be retracted. Read
  `.descriptor.db.status` from `/tmp/brew-cves.json` and ignore the standalone command.
- **A diff came back suspiciously clean on a huge version jump.** Check `.ahead` against
  `.commits|length` before believing it (step 4a). The compare API truncates silently at 250
  commits / 300 files; `libomp` 22.1.8→23.1.0 sampled 250 of **23,416** commits and greped clean.
  A version span this wide is not reviewable through this skill at all — say so rather than
  implying it passed.
- **The truncation check reports `complete` for a gitlab / bitbucket / git formula.** It is telling
  you nothing: only `github.sh` writes `.ahead`, and `null > N` is `false` in jq, so the two-arm
  form of that check falls through to "complete" for the other three adapters and prints
  `complete: null commits`. Use the three-arm form in step 4a and read the per-kind table beside it.
  `bitbucket` is the one that silently truncates without any total to compare against — 100 commits
  and 200 files, unpaginated.
- **A formula resolves to `{}` even after re-spelling the version with `_` and `-`.** Before calling
  it MANUAL, re-run the tag lookup with `--paginate`. `github.sh` fetches a single tag page and
  GitHub does not order it usefully; `mozilla/nss`'s first page is entirely 2000s-era refs, so its
  current release is invisible to the adapter. A tag found only by the paginated lookup means the
  adapter cannot drive this formula — classify MANUAL and name the tag, do not feed it to
  `fetch-diff` and present the result as adapter-verified.
- **grype DB download fails** (first run, or when the cached DB on the machine is stale / offline): report "CVE scan unavailable — falling back to no security classification", then process every formula through the age gate only. Still useful, just less informative. To preempt this on a fresh machine, run `grype db update` once before the first `/review-brew-outdated` invocation.
- **Source A returns 0 for a project that clearly ships security fixes.** Normal — it means the
  project does not file GitHub advisories, not that the release is clean. OpenSSL is the standing
  example (publishes on `openssl-library.org`). Fall through to B, then C; never treat an empty A
  as an all-clear.
- **Source B returns only `OSV-…` ids.** Those are OSS-Fuzz crash reports, not published
  advisories — filter them out. A repo can carry dozens (libheif: 16) and reporting them as
  advisories would manufacture a SECURITY classification out of nothing.
- **api.osv.dev unreachable or slow.** Non-fatal: note "OSV lookup unavailable" and rely on A and
  C. Use `--max-time`; the endpoint occasionally hangs rather than erroring.
- **A and C disagree on the count.** Trust A. C reads commit subjects and patch text, which
  routinely mention *previously* fixed advisories in comments and regression-test names; A is keyed
  on `patched_versions` and cannot make that mistake. Reconcile before writing the summary rather
  than reporting a union.
- **`gh api compare` 404s** (force-pushed or rewritten history upstream): classify as **MANUAL** with reason "upstream compare unavailable".
- **GitHub rate limit** (403 with `x-ratelimit-remaining: 0`): stop processing, report remaining formulae as skipped with the reason "github rate limit".
- **Every GitHub formula fails identically from the first call** (`tags fetch failed` for each, exit 3): this is local `gh` auth, not an upstream fault — but it arrives dressed as one, because exit 3 means "upstream API / network failure" in the table above. A genuine rate limit or outage degrades partway through a run; this is uniform from call one. `adapters/github.sh` prints gh's/op's own stderr precisely so the two can be told apart — read it before classifying anything as MANUAL. Confirm with a single `bash "$SKILL_DIR/adapters/github.sh" resolve-tag cli/cli 2.96.0`, and if it is auth, `export GH_TOKEN="$(gh auth token)"` for the run.
- **GitLab API returns `{"message":"404 ..."}` or `{"message":"403 ..."}`**: the project path is wrong (private fork, renamed repo) or the instance requires auth. Classify as **MANUAL** with the returned message as the reason.
- **Bitbucket `/diff/` times out** (Atlassian edge occasionally 504s on large spans like x265 4.1→4.2 = 1.7 MB patch): retry once with `curl --max-time 30`, then fall back to diffstat-only review — set the meta file, leave the patch empty, and mark the formula REVIEW MANUALLY with reason "bitbucket diff unavailable".
- **`git clone` / `git fetch` for cgit fails** (upstream server offline, network): classify as **MANUAL** with reason "upstream git unreachable". Do NOT delete the cache — a stale cache is better than nothing for the next run.
- **Tag contains `/`** (e.g. `release/x.y`, `refs/tags/foo/bar`): `contains($v)` still matches, but URL-encode the tag when embedding in API paths — GitLab `compare?from=<tag>` accepts URL-encoded refs.
- **`brew info` returns no JSON** (formula renamed or removed): classify as **MANUAL**.

## Why these choices

- **syft + grype, but never as the only security signal.** Advisory databases are authoritative
  and cheap to query for what they cover. What they cover badly is this repo's centre of mass —
  C/C++ libraries installed by Homebrew, which reach the databases only after NVD assigns a CPE.
  On 2026-08-28 grype produced no match for the CVE- and GHSA-fixing releases of `glib`,
  `python@3.10`, `python@3.12`, and `postgresql@15` / `libpq` (same source tree); every
  one was caught only by reading
  the releases themselves. The one formula it did flag, `imagemagick`, it flagged on four stale
  CPE matches (`CVE-2014-9826`, `CVE-2016-7538`, `CVE-2017-5506` with empty `fix` arrays, plus a
  2023 entry) and not on any of the ten GHSAs that release actually fixed — the right
  classification for the wrong reason. That run's DB was recorded as seven days old, but the reading
  came from a `grype db status` run alongside the scan, which races the auto-update — treat it as
  unverified. The 2026-09-03 run settles the question with the authoritative field: the scan's own
  `.descriptor.db.status` showed a DB built that morning, `valid: true`, and it still matched none
  of the 11 CVEs in `openssl@3` 3.6.4, the 11 GHSAs in `libheif` 1.23.3, the 6 in `pcre2` 10.48, or
  the 2 in `libde265` 1.1.2 — **30 advisories missed on a current database**. (Count libheif at A's
  11, not the greps' 13: three of those are false positives this skill's own step 4a discards, and
  padding the indictment with them would repeat the mistake being documented.) Of the 13 brew matches
  it did return, 12 had an empty `fix` array and four of the formulae (`imagemagick`, `libtiff`,
  `pixman`, `redis`) were not outdated at all. Freshness is not part of this story; the purl gap is
  the whole of it.
- **Step 4a exists because the two blind spots align.** A release that is days old is both too
  new for NVD enrichment to reach grype *and* too new to pass the age gate into diff review.
  Under the original ordering, freshness closed both eyes at once — systematically, not randomly.
  On 2026-08-28 `libheif` 1.23.2 (eight GHSAs, two days old, two of them rated critical) landed in
  WAIT and was never looked at; it surfaced only because it happened to be a dependency of
  `imagemagick`, which was being upgraded for unrelated reasons. Reading the changelog for every
  candidate costs one extra adapter call per WAIT formula and closes that hole.
- **Both greps, not one.** Matching the strict `CVE-`/`GHSA-` ID forms is necessary but not
  sufficient: scope decides what you find. Projects split into two camps and neither camp is the
  minority here. ImageMagick and libheif cite the advisory in the fix's commit subject and never
  in-tree, so subjects find 10 and 8 while added patch lines find 0 and 6. glib and CPython
  record advisories in `NEWS` / `Misc/NEWS.d` and say nothing in the subject, so subjects find 0
  and 2 while patch lines find 1 and 8. Picking either scope alone drops real findings — subjects
  alone would have missed glib's CVE-2026-15588, the one advisory grype missed too. The patch
  scope's cost is noise rather than falsity, and it is bounded: a changelog-format migration can
  re-add years of old entries at once, which is why step 4a triages hits by reading the matched
  line instead of trusting the count.
- **Three advisory sources, because each one is blind somewhere the others are not.** This is the
  same argument as "both greps", one level up. Source A (GitHub advisories) is the most accurate
  and the only one carrying severity, but it is empty for any project that files elsewhere —
  OpenSSL, the single largest attack surface in the Cellar, returns zero. Source B (OSV `GIT`)
  catches exactly that case and nothing else here: it returned all 11 OpenSSL CVEs and zero for
  libheif, whose GHSAs are not in OSV at all. Source C (greps) is the only thing left for projects
  that file nothing anywhere — gnupg, curl, nss and libgcrypt were invisible to A, B *and* grype on
  2026-09-03, and their releases still carried real memory-safety fixes. Running one source and
  calling it done reproduces the exact failure this skill was written to stop.
- **Severity is a reason to prefer Source A, not a nice-to-have.** The 2026-09-03 report ranked
  libheif's eleven advisories flat because commit subjects carry no severity. One of them,
  `GHSA-x8r2-mggj-j6wr`, is critical at CVSS 9.8. A user deciding how urgently to run the upgrade
  command needs that number, and only A has it.
- **10-day gate kept from Renovate policy.** The rest of this repo (`lazy-lock.json`, `aqua.yaml`) already uses `minimumReleaseAge: 10 days` via Renovate. Matching the threshold here keeps expectations consistent.
- **No automatic `brew upgrade`.** Homebrew upgrades touch `/opt/homebrew` and can trigger cascading dependency upgrades. The user runs the command so they can eyeball it and interrupt if something looks off.
- **Cellar-wide syft scan.** Per-formula scans would duplicate work; one pass is O(minutes) and feeds every downstream decision.
- **Host adapters instead of github-only.** Many Homebrew formulae (every GNU project, VideoLAN libs, x265, inria libs) live outside GitHub. Leaving them MANUAL was pushing ~30% of `brew outdated` into untriaged territory. GitLab and Bitbucket both expose a compare-equivalent API; cgit/Savannah doesn't, but a shallow bare clone at `/tmp/brew-review-cache/` works everywhere and gives local `git diff` access — the same heuristic grep then applies uniformly.
- **Patch-file + meta-file split.** Each adapter produces different JSON shapes, but the HIGH heuristics are purely patch-text regexes. Normalizing to `/tmp/brew-diff-<name>.patch` (one unified diff) + `/tmp/brew-diff-<name>-meta.json` (commits + files) lets the scan logic stay adapter-agnostic.
- **Reports saved under `.local/`, not `/tmp/`.** Chat summaries scroll away and `/tmp/` is cleared by macOS's periodic cleanup (and on reboot). `.local/` is gitignored at the dotfiles repo root, so reports persist with the repo (visible to `ls -A`, easy to grep across runs) without entering version control.
