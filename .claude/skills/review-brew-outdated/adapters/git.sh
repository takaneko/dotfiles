#!/usr/bin/env bash
# Generic git adapter for cgit / Savannah / self-hosted repos.
#
# Usage:
#   git.sh init         <name> <clone_url>
#     Sets up (or refreshes) a bare clone cache. Must be called before
#     resolve-tag / fetch-diff.
#   git.sh resolve-tag  <name> <version>
#   git.sh fetch-diff   <name> <old_ref> <new_ref> <out_prefix>
#
# Cache lives at ${XDG_CACHE_HOME:-$HOME/.cache}/brew-review/<name>.git.
# Chosen over /tmp to avoid shared-world-writable hijack (another process as
# the same user pre-creating the dir with a tampered remote config). If an
# existing path is not a valid bare git dir, it is removed before cloning.

set -euo pipefail

die() { echo "git.sh: $*" >&2; exit "${2:-3}"; }

cache_path() {
  local name=$1
  printf '%s/brew-review/%s.git' "${XDG_CACHE_HOME:-$HOME/.cache}" "$name"
}

op=${1:?op}; shift

case "$op" in
  init)
    name=${1:?name}; url=${2:?clone_url}
    cache=$(cache_path "$name")
    mkdir -p "$(dirname "$cache")"
    if [ -e "$cache" ] && ! git -C "$cache" rev-parse --is-bare-repository >/dev/null 2>&1; then
      echo "git.sh: removing stale/invalid cache at $cache" >&2
      rm -rf "$cache"
    fi
    if [ ! -d "$cache" ]; then
      git clone --bare --no-tags "$url" "$cache" >&2 \
        || die "clone failed: $url"
    fi
    git -C "$cache" fetch --tags --quiet \
      || die "fetch failed for $name"
    ;;

  resolve-tag)
    name=${1:?name}; version=${2:?version}
    cache=$(cache_path "$name")
    [ -d "$cache" ] || die "cache missing for $name (run 'init' first)" 2
    # Reject tag names beginning with '-': they cannot safely be passed to git
    # plumbing as positional args (would be parsed as options). Defense-in-depth
    # — downstream calls all use `--end-of-options` as well.
    # `|| true` on the grep prevents pipefail from killing the script when
    # `git tag -l` matches zero tags (grep then exits 1) — we need to fall
    # through to the empty-string check and emit '{}'.
    tag=$(git -C "$cache" tag -l "*${version}*" | { grep -v '^-' || true; } | head -1)
    if [ -z "$tag" ]; then
      echo '{}'
      exit 0
    fi
    # `rev-parse --end-of-options` is a no-op that pollutes stdout, so rely on
    # the `grep -v '^-'` filter above to reject dash-prefixed tags.
    sha=$(git -C "$cache" rev-parse "$tag")
    date=$(git -C "$cache" log -1 --format=%cI --end-of-options "$tag")
    jq -n --arg n "$tag" --arg s "$sha" --arg d "$date" \
      '{name: $n, sha: $s, date: $d}'
    ;;

  fetch-diff)
    name=${1:?name}; old=${2:?old_ref}; new=${3:?new_ref}; out=${4:?out_prefix}
    cache=$(cache_path "$name")
    [ -d "$cache" ] || die "cache missing for $name (run 'init' first)" 2

    commits_tmp=$(mktemp); files_tmp=$(mktemp)
    trap 'rm -f "$commits_tmp" "$files_tmp"' EXIT

    # `-z` makes git use NUL as record separator; `%n` delimits fields within
    # each record. This tolerates tabs and multi-line subjects in commits.
    git -C "$cache" log -z --format='%h%n%cI%n%an%n%s' --end-of-options "${old}..${new}" \
      | jq -R -s 'split("\u0000") | map(select(length > 0) | split("\n")
                  | {sha: .[0], date: .[1], author: .[2],
                     message: (.[3:] | join(" "))})' \
      > "$commits_tmp"

    # `--name-status` preserves A/M/D/R/C/T so the MEDIUM heuristic can tell
    # "20 new files added" from "20 files modified". We keep the LF-delimited
    # form (not `-z`) so git-quoting of unusual pathnames survives as-is —
    # any filename that needs escaping will appear quoted in the output,
    # which the downstream scan can treat as an anomaly in its own right.
    git -C "$cache" diff --name-status --end-of-options "${old}..${new}" \
      | jq -R -s 'split("\n") | map(select(length > 0) | split("\t") as $f
                  | if ($f[0] | test("^[RC]")) then
                      {filename: $f[2], oldpath: $f[1], status: ($f[0][:1])}
                    else
                      {filename: $f[1], status: $f[0]}
                    end)' \
      > "$files_tmp"

    jq -n --slurpfile c "$commits_tmp" --slurpfile f "$files_tmp" \
      '{commits: $c[0], files: $f[0]}' > "${out}-meta.json"

    git -C "$cache" diff --end-of-options "${old}..${new}" > "${out}.patch"
    ;;

  *)
    die "unknown op: $op" 2
    ;;
esac
