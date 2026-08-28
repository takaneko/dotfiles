#!/usr/bin/env bash
# GitHub adapter for review-brew-outdated.
#
# Usage:
#   github.sh resolve-tag <owner/repo> <version>
#     → JSON {name, sha, date} on stdout, or {} if no tag matches.
#   github.sh fetch-diff  <owner/repo> <old_sha> <new_sha> <out_prefix>
#     writes <out_prefix>.patch (raw unified diff) and
#     <out_prefix>-meta.json ({commits, files}).
#
# Exit codes:
#   0 = success
#   2 = invalid usage / unknown op
#   3 = upstream error (404 / rate limit / network)

set -euo pipefail

die() { echo "github.sh: $*" >&2; exit "${2:-3}"; }

# How to invoke gh. Where gh is authenticated through a 1Password shell plugin,
# `gh` is an alias/function in ~/.config/op/plugins.sh; this script is a child
# process and inherits neither, so a bare `gh` would run unauthenticated and
# every call would fail. 1Password's documented fix is to wrap in `op plugin
# run`: https://www.1password.dev/cli/shell-plugins/troubleshooting
#
# Gate on "can gh authenticate itself?", NOT on "is op installed?" — op ships to
# every machine via aqua.yaml, so keying off its presence would force the op
# path even where `gh auth login` already works, breaking it.
#
# Use `gh auth status` (exit 1 when unauthenticated or the token is invalid),
# NOT `gh auth token`: the latter happily prints a stale token left in the macOS
# keychain even with no hosts.yml and no working login, so it reports success on
# a machine where every API call then fails. The env checks come first so the
# CI case short-circuits before the ~0.1s probe.
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ] || gh auth status >/dev/null 2>&1; then
  gh_run() { gh "$@"; }
elif command -v op >/dev/null 2>&1; then
  # `op plugin init` can register a plugin globally or scoped to a directory,
  # and it resolves the scoped kind by walking up from the CWD. Which one is in
  # effect is machine-local state we cannot see from here, so run op from our
  # own directory: that satisfies a plugin scoped to this checkout and is
  # harmless for a global one, whatever CWD the caller happens to have.
  # Redirections in the callers stay outside this subshell, so relative
  # <out_prefix> paths still resolve against the caller's CWD.
  gh_run() { ( cd "$SELF_DIR" && op plugin run -- gh "$@" ); }
else
  # No credentials anywhere. Let gh fail with its own message, which names the
  # fix ("gh auth login" / populate GH_TOKEN) better than anything we'd print.
  gh_run() { gh "$@"; }
fi

op=${1:?op}; shift

case "$op" in
  resolve-tag)
    repo=${1:?repo}; version=${2:?version}
    # gh's stderr is deliberately NOT suppressed here. A local auth failure and
    # an upstream 404 both surface as `die` + exit 3, and gh's/op's own message
    # is the only thing that tells them apart.
    tag=$(gh_run api "repos/${repo}/tags?per_page=100" \
      | jq --arg v "$version" '[.[] | select(.name | contains($v))] | .[0]') \
      || die "tags fetch failed for $repo"
    if [ -z "$tag" ] || [ "$tag" = "null" ]; then
      echo '{}'
      exit 0
    fi
    name=$(jq -r '.name' <<<"$tag")
    sha=$(jq -r '.commit.sha' <<<"$tag")
    date=$(gh_run api "repos/${repo}/commits/${sha}" --jq '.commit.committer.date') \
      || die "commit date fetch failed for ${repo}@${sha}"
    jq -n --arg n "$name" --arg s "$sha" --arg d "$date" \
      '{name: $n, sha: $s, date: $d}'
    ;;

  fetch-diff)
    repo=${1:?repo}; old=${2:?old}; new=${3:?new}; out=${4:?out_prefix}
    # `has_patch` distinguishes files where GitHub omits .patch (binary files,
    # files over ~4MB) from files with real patch bodies. The raw patch scan
    # can't see these; the MEDIUM heuristic must rely on meta.has_patch=false
    # + status="added" to catch binary-blob additions.
    # One fetch, two jq passes — `--jq` runs client-side, so filtering twice at
    # the API would download the whole compare payload (MBs on large spans)
    # twice. Same tmp+jq shape as gitlab.sh / bitbucket.sh / git.sh.
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    gh_run api "repos/${repo}/compare/${old}...${new}" > "$tmp" \
      || die "compare fetch failed for ${repo} ${old}...${new}"
    jq '{ahead: .ahead_by,
         commits: [.commits[] | {sha: .sha[0:7], author: .commit.author.name,
                                  date: .commit.author.date,
                                  message: (.commit.message | split("\n")[0])}],
         files: [.files[] | {filename, status, additions, deletions,
                              has_patch: (.patch != null)}]}' \
      "$tmp" > "${out}-meta.json" \
      || die "compare meta parse failed for ${repo} ${old}...${new}"
    jq -r '.files[] | .patch // empty' "$tmp" > "${out}.patch" \
      || die "compare patch parse failed for ${repo} ${old}...${new}"
    ;;

  *)
    die "unknown op: $op" 2
    ;;
esac
