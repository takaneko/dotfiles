# Evidence and rationale

Why this skill is shaped the way it is, and the measurements behind each decision. Read this when a
step's instruction looks like overkill, when a run's results contradict what SKILL.md says to
expect, or before changing any of the four design decisions below.

Every table here is from a real run, not a hypothetical.

## The 2026-09-03 run — why three advisory sources

Three of the four formulae that mattered were found by exactly **one** source each, and the sources
disagreed about the fourth.

| Formula | A (GitHub) | B (OSV GIT) | C (greps) | grype |
|---|---|---|---|---|
| `libheif` 1.23.2→1.23.3 | **11**, one *critical* CVSS 9.8 | 0 | 13 — three wrong, one missed | 0 |
| `pcre2` 10.47→10.48 | **6**, no noise | 0 | 6, after triaging 13 historical IDs | 0 |
| `libde265` 1.1.1→1.1.2 | **2** | 0 | 2 | 0 |
| `openssl@3` 3.6.3→3.6.4 | 0 | **11** | 11 | 0 |
| `gnupg`, `curl`, `nss`, `libgcrypt` | 0 | 0 | 0 | 1 stale |

**Each source is blind somewhere the others are not.** Source A (GitHub advisories) is the most
accurate and the only one carrying severity, but it is empty for any project that files elsewhere —
OpenSSL, the single largest attack surface in the Cellar, returns zero. Source B (OSV `GIT`) catches
exactly that case and nothing else here: it returned all 11 OpenSSL CVEs and zero for libheif, whose
GHSAs are not in OSV at all. Source C (greps) is the only thing left for projects that file nothing
anywhere — gnupg, curl, nss and libgcrypt were invisible to A, B *and* grype, and their releases
still carried real memory-safety fixes. Running one source and calling it done reproduces the exact
failure this skill was written to stop.

### Where A and C disagree, prefer A

On libheif the greps counted 13 by reading code comments about *older* fixes as current
(`GHSA-jc8f-p23p-5hjg` was patched in v1.23.1, `GHSA-2c3g-p585-8rpq` in 1.19.6,
`GHSA-prcj-g5xh-rw95` is not an advisory at all) while simultaneously dropping
`GHSA-73p7-m7gg-w2jv` by misreading it as a prior incomplete fix. 13 − 3 + 1 = 11 = A's count.

The changelog-noise problem applies to **code comments too**, and C cannot tell you that
`GHSA-x8r2-mggj-j6wr` is CVSS 9.8 while the other ten are not.

### Severity is a reason to prefer A, not a nice-to-have

The first 2026-09-03 report ranked libheif's eleven advisories flat, because commit subjects carry
no severity. One of them, `GHSA-x8r2-mggj-j6wr`, is critical at CVSS 9.8. A user deciding how
urgently to run the upgrade command needs that number, and only A has it.

### Do not substitute `osv-scanner` for any of this

Tested against the same `/tmp/brew-sbom.json`: 39 vulnerable packages, **none of them an outdated
formula**. Every hit was a Go/Rust/Python dependency vendored inside a bottle, which `brew upgrade`
cannot act on. It shares grype's purl gap and adds noise.

## The 2026-08-28 run — why both greps, not one

Source C alone, before A and B existed:

| Formula | subjects | added patch lines |
|---|---|---|
| `imagemagick` 7.1.2-29 → -30 | **10 GHSAs** | 0 |
| `libheif` 1.23.1 → 1.23.2 | **8 GHSAs** | 6 (a subset of subjects) |
| `glib` 2.88.2 → 2.88.3 | 0 | **CVE-2026-15588** |
| `python@3.10` 3.10.20 → 3.10.21 | 2 | **8** (6 additional, all genuine) |
| `fontconfig`, `imath`, `little-cms2`, `sdl3`, `tmux` | 0 | 0 |

Matching the strict `CVE-` / `GHSA-` ID forms is necessary but not sufficient: **scope** decides
what you find, and projects split into two camps with neither in the minority. ImageMagick and
libheif cite the advisory in the fix's commit subject and never in-tree. glib and CPython record
advisories in `NEWS` / `Misc/NEWS.d` and say nothing in the subject.

Picking either scope alone drops real findings — subjects alone would have missed glib's
CVE-2026-15588, the one advisory grype missed too. The patch scope's cost is noise rather than
falsity, and it is bounded: a changelog-format migration can re-add years of old entries at once,
which is why step 4a triages hits by reading the matched line instead of trusting the count.

When there is no commit list at all — a shallow tag-to-tag diff, or the step-3a tarball path — the
patch scope is the only signal available.

## Why grype is never the only security signal

Advisory databases are authoritative and cheap to query for what they cover. What they cover badly
is this repo's centre of mass: **C/C++ libraries installed by Homebrew have no purl→advisory mapping
in the GitHub Advisory Database**, so they match only once NVD assigns a CPE, which lags by weeks to
months.

On 2026-08-28 grype produced no match for the CVE- and GHSA-fixing releases of `glib`,
`python@3.10`, `python@3.12`, and `postgresql@15` / `libpq` (same source tree); every one was caught
only by reading the releases themselves. The one formula it did flag, `imagemagick`, it flagged on
four stale CPE matches (`CVE-2014-9826`, `CVE-2016-7538`, `CVE-2017-5506` with empty `fix` arrays,
plus a 2023 entry) and **not** on any of the ten GHSAs that release actually fixed — the right
classification for the wrong reason.

That run's DB was recorded as seven days old, but the reading came from a `grype db status` run
alongside the scan, which races the auto-update (see below) — treat it as unverified.

**The 2026-09-03 run settles it with the authoritative field.** The scan's own
`.descriptor.db.status` showed a DB built that morning, `valid: true`, and it still matched none of
the 11 CVEs in `openssl@3` 3.6.4, the 11 GHSAs in `libheif` 1.23.3, the 6 in `pcre2` 10.48, or the 2
in `libde265` 1.1.2 — **30 advisories missed on a current database**.

> Count libheif at A's 11, not the greps' 13: three of those are false positives step 4a discards,
> and padding the indictment with them would repeat the mistake being documented.

Of the 13 brew matches grype did return, 12 had an empty `fix` array and four of the formulae
(`imagemagick`, `libtiff`, `pixman`, `redis`) were not outdated at all. **Freshness is not part of
this story; the purl gap is the whole of it.**

### The `grype db status` race

grype auto-updates its DB when a scan starts (the default; no `GRYPE_DB_AUTO_UPDATE` is set here)
and `syft` takes minutes to build the SBOM first, so a `grype db status` run alongside the scan
reads the *previous* cache and reports a staleness that no longer applies by the time grype runs.

Measured 2026-09-03: `grype db status` reported `built 2026-08-27` / `Status: invalid` while the
scan it was racing recorded `built 2026-09-03T06:30:55Z` / `valid: true`. The whole "stale DB"
finding had to be retracted. Read `.descriptor.db.status` from the scan output; it is written by the
scan itself, so it cannot race.

## Why step 4a runs for WAIT formulae too

**The two blind spots align.** A release that is days old is both too new for NVD enrichment to
reach grype *and* too new to pass the age gate into diff review. Under the original ordering,
freshness closed both eyes at once — systematically, not randomly.

On 2026-08-28 `libheif` 1.23.2 (eight GHSAs, two days old, two of them rated critical) landed in
WAIT and was never looked at. It surfaced only because it happened to be a dependency of
`imagemagick`, which was being upgraded for unrelated reasons. Reading the changelog for every
candidate costs one extra adapter call per WAIT formula and closes that hole.

## Why diff truncation is a classification, not a footnote

The compare API truncates silently at 250 commits / 300 files, and a truncated diff greps exactly
like a complete clean one. Measured 2026-09-03:

| Formula | span | sampled |
|---|---|---|
| `libomp` 22.1.8→23.1.0 | **23,416** commits | 250 |
| `mise` | 2,444 commits | 250 |
| `usage` | 622 commits | 250 |
| `curl` | 525 commits | 250 |
| `nss` (resolved by hand) | 52 commits, all present | hit the 300-**file** cap |

**Every one of them greped clean.** A version span as wide as libomp's is not reviewable through
this skill at all — say so rather than implying it passed.

## Standing design decisions

- **10-day gate kept from Renovate policy.** The rest of this repo (`lazy-lock.json`, `aqua.yaml`)
  already uses `minimumReleaseAge: 10 days` via Renovate. Matching the threshold here keeps
  expectations consistent.
- **No automatic `brew upgrade`.** Homebrew upgrades touch `/opt/homebrew` and can trigger cascading
  dependency upgrades. The user runs the command so they can eyeball it and interrupt if something
  looks off.
- **Cellar-wide syft scan.** Per-formula scans would duplicate work; one pass is O(minutes) and feeds
  every downstream decision.
- **Host adapters instead of github-only.** Many Homebrew formulae (every GNU project, VideoLAN libs,
  x265, inria libs) live outside GitHub. Leaving them MANUAL was pushing ~30% of `brew outdated` into
  untriaged territory. GitLab and Bitbucket both expose a compare-equivalent API; cgit/Savannah does
  not, but a shallow bare clone works everywhere and gives local `git diff` access — the same
  heuristic grep then applies uniformly.
- **Patch-file + meta-file split.** Each adapter produces different JSON shapes, but the HIGH
  heuristics are purely patch-text regexes. Normalizing to `/tmp/brew-diff-<name>.patch` (one unified
  diff) + `/tmp/brew-diff-<name>-meta.json` (commits + files) lets the scan logic stay
  adapter-agnostic.
- **Reports saved under `.local/`, not `/tmp/`.** Chat summaries scroll away and `/tmp/` is cleared by
  macOS's periodic cleanup (and on reboot). `.local/` is gitignored at the dotfiles repo root, so
  reports persist with the repo (visible to `ls -A`, easy to grep across runs) without entering
  version control.
