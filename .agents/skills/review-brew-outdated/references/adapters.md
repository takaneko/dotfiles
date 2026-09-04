# Adapter reference

Everything about driving `$SKILL_DIR/adapters/<kind>.sh`. Read this when a tag will not resolve,
a fetch fails, a diff looks wrong, or you need the date-parsing fallback.

`$SKILL_DIR` is `$HOME/dotfiles/.agents/skills/review-brew-outdated`. `.claude/skills` is a symlink
pointing there, so either path reaches the same files.

## Calling convention

All four adapters expose the same two verbs with the same JSON shapes:

```bash
bash "$SKILL_DIR/adapters/<kind>.sh" resolve-tag <key...> "<VERSION>"
# → {"name": "v1.2.3", "sha": "...", "date": "2026-04-15T..."}
# → {} if no tag contains the version string

bash "$SKILL_DIR/adapters/<kind>.sh" fetch-diff <key...> "<OLD_REF>" "<NEW_REF>" "$OUT"
# writes $OUT.patch      — raw unified diff text (input to the HIGH heuristic grep)
# writes $OUT-meta.json  — {commits, files} (+ {ahead} on github) (input to the MEDIUM heuristics)
```

`<key...>` is whatever the step-3 kind table recorded: `<owner>/<repo>` for github,
`<host> <project_path>` for gitlab, `<workspace> <repo_slug>` for bitbucket.

> **`git` kind is the exception to the uniform `<key...>` convention.** Its `resolve-tag` takes only
> `<name> <version>` — the clone URL is **not** passed here (it is used solely by the one-time
> `init` in step 3). Likewise git's `fetch-diff` is `<name> <old_ref> <new_ref> <out_prefix>`, with
> no URL. Passing the clone URL into `resolve-tag` / `fetch-diff` shoves the version into the wrong
> slot, so every tag silently resolves to `{}`.

`git` kind also needs a one-time init per formula before either verb:

```bash
bash "$SKILL_DIR/adapters/git.sh" init <name> <CLONE_URL>
```

This clones a bare repo into `${XDG_CACHE_HOME:-$HOME/.cache}/brew-review/<name>.git/`, reused on
later runs, with stale/invalid caches auto-removed before re-cloning.

## Exit codes

| Exit | Meaning | Action |
|---|---|---|
| `0` | Success, both files written | Run the heuristic scan. |
| `2` | Invalid usage (adapter bug) | Treat as MANUAL and flag the bug in the summary. |
| `3` | Upstream API / network failure | Mark REVIEW MANUALLY with the reason from stderr. **For `bitbucket` specifically**, exit 3 with an empty `$OUT.patch` means `/diff/` timed out — `$OUT-meta.json` (commits + filenames) is still populated and usable for a MEDIUM-only scan. |

## `gh` authentication inside adapters

The adapters run as **child processes**, which inherit neither shell aliases nor functions. Where
`gh` is authenticated through a 1Password shell plugin (an alias/function in
`~/.config/op/plugins.sh`), that wrapper does not reach them. `adapters/github.sh` handles this
itself — it falls back to `op plugin run -- gh` when `gh` cannot authenticate on its own — so
nothing needs doing per-run.

But if you ever lift a `gh` call out of the adapter into a standalone script, it will hit the same
wall. The `gh api` calls SKILL.md runs inline (source A in step 4a, the author cross-check in
step 6) are fine: they execute in the top-level shell, where the wrapper is defined.

## Tag-resolution traps

Adapters apply a `contains("<VERSION>")` match against upstream tag listings. Tag naming is not
standardised — Homebrew's `1.6.58` may appear as `v1.6.58`, `libpng-1.6.58`, `release-1.6.58` — so
substring match is the lowest common denominator that works across all hosts. It has four distinct
failure modes, and the first two interact.

### 1. Variant-tag shadowing — returns the *wrong* tag

A suffixed variant can outrank the plain release tag: `contains("4.1.0")` may return
`v4.1.0-cqp-extended` (an experimental/fork tag) instead of `v4.1.0`, silently corrupting the diff
base. This bites hardest on the OLD/base ref, where a wrong tag inflates the diff with unrelated
changes.

When more than one tag matches, prefer the tag that is *exactly* the expected version
(`v<VERSION>` / `<VERSION>` / `<name>-<VERSION>`) over any longer suffixed sibling. If the adapter
handed back a suffixed variant, re-list the tags and pick the exact match by hand before calling
`fetch-diff`. Confirmed live 2026-09-03: `mise` 2026.9.1 resolved to **`vfox-v2026.9.1`**.

### 2. Separator mismatch — returns `{}`

The substring match assumes upstream spells the version the way Homebrew does. Plenty of projects
do not: curl tags `8.22.0` as `curl-8_22_0`, so `contains("8.22.0")` misses *both* refs and the
formula reads as "tag not found" → MANUAL, even though the repo resolved fine and the tags are
right there.

`{}` means "no tag *contained that exact string*", which is not the same as "no tag for this
release". Before accepting it from a repo that plainly exists, retry with `.` replaced by `_` (and
by `-`), or list the tags and pick by eye:

```bash
gh api "repos/<owner>/<repo>/tags?per_page=100" --paginate -q '.[].name' \
  | grep -F "$(echo '<VERSION>' | tr . _)"
```

**Traps 1 and 2 are one procedure, not two — fixing the separator re-exposes the shadowing trap.**
Confirmed on curl 8.22.0: once `8_22_0` matches, the tag list leads with `rc-8_22_0-3`,
`rc-8_22_0-2`, `rc-8_22_0-1` and only *then* `curl-8_22_0`. Taking `.[0]` at that point pins a
release candidate. Always re-apply the exact-match preference after re-spelling the version.

### 3. Tag beyond the adapter's first page — also returns `{}`, and no re-spelling helps

**`--paginate` above is load-bearing, and the adapter does not have it.** `github.sh resolve-tag`
issues a single `tags?per_page=100`, and GitHub does not return that page in any useful order — for
a repo with many tags the newest release may simply not be on it.

`nss` is the standing case: page 1 is 2000s-era refs (`travisWebshell_03082000_BASE`,
`nss_20021204`, …) with **no `NSS_3_*` tag at all**, so the adapter returns `{}` for `mozilla/nss`
no matter how the version is spelled. Measured 2026-09-04: the paginated command finds
`NSS_3_128_RTM` and `NSS_3_128_BETA1`; without `--paginate` it exits 1 with no output.

For `nss` — and any formula where the paginated lookup finds a tag the adapter did not — classify
**MANUAL** with reason "tag beyond adapter's first tag page", and note the tag you found by hand so
the user can review the release themselves. **Do not hand `fetch-diff` a tag the adapter never
produced and report the result as an adapter-verified diff.**

### 4. Base tag absent upstream — substitute, do not give up

If only the **installed/base** version resolves to `{}` (latest is fine), do not jump to MANUAL.
Some upstreams skip or never tag an intermediate release — real case: `libmicrohttpd` 1.0.5 has no
tag on the git.gnunet.org mirror, which jumps `v1.0.4 → v1.0.6`. List the tags, pick the **nearest
lower** tag as the base, and diff that → latest as a **conservative superset**: it reviews *more*
than the user's actual upgrade span, never less. Note the substituted base in the summary (e.g.
"base v1.0.5 absent — reviewed v1.0.4→v1.0.6"). This mirrors the lazy-lock skill's
intermediate-commit fallback. Fall back to MANUAL only if no usable lower tag exists.

If the **latest** version resolves to `{}`, there is nothing to diff *to*: record MANUAL with
reason "tag '<version>' not found".

## Parsing the `date` field

**The `date` value is not always UTC-`Z`.** GitHub returns `…Z`, but the `gitlab` and `git` kinds
return an ISO-8601 timestamp with a numeric offset (`2026-07-14T08:39:09+02:00`, `…-05:00`). jq's
`fromdate` only parses the `Z` form and aborts with
`date "…" does not match format "%Y-%m-%dT%H:%M:%SZ"` on offset timestamps.

```bash
now=$(date +%s)
# gdate (GNU coreutils, installed via brew) handles both the Z form and ±HH:MM offsets:
epoch=$(gdate -d "<date from resolve-tag>" +%s)
age_days=$(( (now - epoch) / 86400 ))
```

Fallback when `gdate` is unavailable — BSD `date` needs `Z`→`+0000`, fractional seconds dropped
(gitlab emits `.000`), and the offset colon stripped before `%z` will parse it:

```bash
d="<date>"
norm=$(echo "${d/Z/+0000}" | sed -E 's/\.[0-9]+//; s/([+-][0-9][0-9]):([0-9][0-9])$/\1\2/')
epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$norm" +%s)
```

## Diff truncation, per kind

Compare endpoints cap their response and say so nowhere in the text you grep, so a truncated diff
greps exactly like a complete clean one. Only `github.sh` gives you the means to detect it: it
records the real span in `.ahead`.

| kind | cap | detectable? |
|---|---|---|
| `github` | 250 commits / 300 files | **yes** — `.ahead` vs `.commits` length, and `.files` length `>= 300` |
| `bitbucket` | 100 commits (`pagelen=100`), 200 files (`pagelen=200`), neither paginated | **no** — no total is fetched. Treat a diff at exactly 100 commits or 200 files as truncated. |
| `gitlab` | server-side compare limit, instance-dependent | **no** — treat a suspiciously round or huge span as unverified |
| `git` | none — local clone, full history | n/a, always complete |

**Why the step-4a check needs its `.ahead == null` arm.** Only `github.sh` emits `ahead`;
`gitlab.sh`, `bitbucket.sh` and `git.sh` write `{commits, files}` alone. jq evaluates `null > 3` as
`false`, so a two-arm form falls through to the else branch and prints
`complete: null commits, N files` for every non-GitHub formula — a fabricated all-clear, which is
exactly the failure the check exists to prevent.
