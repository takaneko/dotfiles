# Failure modes

What each failure means and what to do about it. Read the entry that matches your symptom — most of
these are **expected behaviour that looks like a malfunction**, and the wrong reaction to several of
them is to report a clean result.

## grype

- **grype reports nothing for a formula that plainly fixed a vulnerability.** Expected, not a
  malfunction. Homebrew C/C++ libraries have no purl→advisory mapping in the GitHub Advisory
  Database, so they match only once NVD assigns a CPE, which lags by weeks to months. Step 4a is the
  compensating control. **Never read a grype miss as evidence of safety.** Do not reach for
  `grype db update` as the remedy — a current DB does not close the gap; see
  `references/evidence.md`, "Why grype is never the only security signal".
- **grype matches ancient CVEs with an empty `fix` array.** Also expected. Name-based CPE matching,
  plus Homebrew version strings it cannot parse (`7.1.2-29` is a patch counter, not a semver
  prerelease, and grype orders it *before* `7.1.2`), produce stale hits. Treat a grype hit as a
  prompt to read the release notes, never as the finding itself.
- **`grype db status` disagrees with the scan.** Not a fault — a race. grype auto-updates at scan
  start and `syft` runs for minutes beforehand, so a status check launched alongside the run reads
  the pre-update cache. Read `.descriptor.db.status` from `/tmp/brew-cves.json` and ignore the
  standalone command.
- **grype DB download fails** (first run, or a stale cache / offline machine): report "CVE scan
  unavailable — falling back to no security classification", then process every formula through the
  age gate only. Still useful, just less informative. To preempt this on a fresh machine, run
  `grype db update` once before the first `/review-brew-outdated` invocation.

## Advisory sources

- **Source A returns 0 for a project that clearly ships security fixes.** Normal — it means the
  project does not file GitHub advisories, not that the release is clean. OpenSSL is the standing
  example (publishes on `openssl-library.org`). Fall through to B, then C; never treat an empty A as
  an all-clear.
- **Source B returns only `OSV-…` ids.** Those are OSS-Fuzz crash reports, not published advisories
  — filter them out. A repo can carry dozens (libheif: 16) and reporting them as advisories would
  manufacture a SECURITY classification out of nothing.
- **api.osv.dev unreachable or slow.** Non-fatal: note "OSV lookup unavailable" and rely on A and C.
  Use `--max-time`; the endpoint occasionally hangs rather than erroring.
- **A and C disagree on the count.** Trust A. C reads commit subjects and patch text, which
  routinely mention *previously* fixed advisories in comments and regression-test names; A is keyed
  on `patched_versions` and cannot make that mistake. Reconcile before writing the summary rather
  than reporting a union.

## Diffs

- **A diff came back suspiciously clean on a huge version jump.** Check `.ahead` against
  `.commits` length before believing it (step 4a). `libomp` 22.1.8→23.1.0 sampled 250 of **23,416**
  commits and greped clean. A version span this wide is not reviewable through this skill at all —
  say so rather than implying it passed.
- **The truncation check reports `complete` for a gitlab / bitbucket / git formula.** It is telling
  you nothing: only `github.sh` writes `.ahead`, and `null > N` is `false` in jq, so a two-arm form
  of that check falls through to "complete" and prints `complete: null commits`. Use the three-arm
  form in step 4a and the per-kind table in `references/adapters.md`. `bitbucket` is the one that
  silently truncates with no total to compare against — 100 commits and 200 files, unpaginated.

## Tag resolution

- **A formula resolves to `{}` even after re-spelling the version with `_` and `-`.** Before calling
  it MANUAL, re-run the tag lookup with `--paginate`. `github.sh` fetches a single tag page and
  GitHub does not order it usefully; `mozilla/nss`'s first page is entirely 2000s-era refs, so its
  current release is invisible to the adapter. A tag found only by the paginated lookup means the
  adapter cannot drive this formula — classify MANUAL and name the tag, do not feed it to
  `fetch-diff` and present the result as adapter-verified. Full detail in
  `references/adapters.md`, "Tag-resolution traps".
- **Tag contains `/`** (e.g. `release/x.y`, `refs/tags/foo/bar`): `contains($v)` still matches, but
  URL-encode the tag when embedding it in API paths — GitLab `compare?from=<tag>` accepts
  URL-encoded refs.

## Hosts and auth

- **Every GitHub formula fails identically from the first call** (`tags fetch failed` for each,
  exit 3): this is local `gh` auth, not an upstream fault — but it arrives dressed as one, because
  exit 3 means "upstream API / network failure". A genuine rate limit or outage degrades partway
  through a run; this is uniform from call one. `adapters/github.sh` prints gh's/op's own stderr
  precisely so the two can be told apart — read it before classifying anything as MANUAL. Confirm
  with a single `bash "$SKILL_DIR/adapters/github.sh" resolve-tag cli/cli 2.96.0`, and if it is
  auth, `export GH_TOKEN="$(gh auth token)"` for the run.
- **`gh api compare` 404s** (force-pushed or rewritten history upstream): classify as **MANUAL**
  with reason "upstream compare unavailable".
- **GitHub rate limit** (403 with `x-ratelimit-remaining: 0`): stop processing, report the remaining
  formulae as skipped with the reason "github rate limit".
- **GitLab API returns `{"message":"404 ..."}` or `{"message":"403 ..."}`**: the project path is
  wrong (private fork, renamed repo) or the instance requires auth. Classify as **MANUAL** with the
  returned message as the reason.
- **Bitbucket `/diff/` times out** (Atlassian's edge occasionally 504s on large spans like
  x265 4.1→4.2 = 1.7 MB patch): retry once with `curl --max-time 30`, then fall back to
  diffstat-only review — keep the meta file, leave the patch empty, and mark the formula REVIEW
  MANUALLY with reason "bitbucket diff unavailable".
- **`git clone` / `git fetch` for cgit fails** (upstream server offline, network): classify as
  **MANUAL** with reason "upstream git unreachable". Do NOT delete the cache — a stale cache is
  better than nothing for the next run.

## Homebrew

- **`brew info` returns no JSON** (formula renamed or removed): classify as **MANUAL**.
