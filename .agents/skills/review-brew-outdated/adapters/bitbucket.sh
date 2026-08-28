#!/usr/bin/env bash
# Bitbucket Cloud adapter.
#
# Usage:
#   bitbucket.sh resolve-tag <workspace> <repo_slug> <version>
#   bitbucket.sh fetch-diff  <workspace> <repo_slug> <old_ref> <new_ref> <out_prefix>
#
# Note on ref-spec convention: Bitbucket's /diff/ and /diffstat/ endpoints use
# <source>..<destination> (newer ref first), opposite of GitHub's
# compare/<OLD>...<NEW>. This script passes <new_ref>..<old_ref> accordingly.
#
# /diff/ returns text/plain raw unified patch, not JSON, and occasionally 504s
# on large spans (e.g. x265 4.1..4.2 = 1.7MB). On failure this script writes an
# empty patch and exits 3 so the caller can downgrade the formula to REVIEW
# MANUALLY.

set -euo pipefail

API="https://api.bitbucket.org/2.0"

die() { echo "bitbucket.sh: $*" >&2; exit "${2:-3}"; }

op=${1:?op}; shift

case "$op" in
  resolve-tag)
    ws=${1:?workspace}; repo=${2:?repo_slug}; version=${3:?version}
    curl -sSf --max-time 30 \
      "${API}/repositories/${ws}/${repo}/refs/tags?pagelen=100&sort=-target.date" \
      | jq --arg v "$version" \
          '.values | [.[] | select(.name | contains($v))] | .[0]
           | if . == null then {}
             else {name: .name, sha: .target.hash, date: .target.date} end' \
      || die "tags fetch failed for ${ws}/${repo}"
    ;;

  fetch-diff)
    ws=${1:?workspace}; repo=${2:?repo_slug}
    old=${3:?old_ref}; new=${4:?new_ref}; out=${5:?out_prefix}
    commits=$(mktemp); diffstat=$(mktemp)
    trap 'rm -f "$commits" "$diffstat"' EXIT

    curl -sSf --max-time 30 \
      "${API}/repositories/${ws}/${repo}/commits/?include=${new}&exclude=${old}&pagelen=100" \
      > "$commits" \
      || die "commits fetch failed for ${ws}/${repo}"
    curl -sSf --max-time 30 \
      "${API}/repositories/${ws}/${repo}/diffstat/${new}..${old}?pagelen=200" \
      > "$diffstat" \
      || die "diffstat fetch failed for ${ws}/${repo}"

    jq -n --slurpfile c "$commits" --slurpfile d "$diffstat" \
      '{commits: ($c[0].values | map({sha: .hash[0:7], author: .author.raw,
                                       date: .date, message: (.message | split("\n")[0])})),
        files: ($d[0].values | map({filename: (.new.path // .old.path),
                                     status, lines_added, lines_removed}))}' \
      > "${out}-meta.json"

    # /diff/ can 504 on large spans; fall back to empty patch + exit 3.
    if ! curl -sSf --max-time 30 \
          "${API}/repositories/${ws}/${repo}/diff/${new}..${old}" \
          > "${out}.patch"; then
      : > "${out}.patch"
      echo "bitbucket.sh: warn: /diff/ unavailable for ${ws}/${repo} ${old}..${new} — HIGH-severity patch scan skipped" >&2
      exit 3
    fi
    ;;

  *)
    die "unknown op: $op" 2
    ;;
esac
