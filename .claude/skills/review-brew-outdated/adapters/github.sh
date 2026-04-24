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

op=${1:?op}; shift

case "$op" in
  resolve-tag)
    repo=${1:?repo}; version=${2:?version}
    tag=$(gh api "repos/${repo}/tags?per_page=100" 2>/dev/null \
      | jq --arg v "$version" '[.[] | select(.name | contains($v))] | .[0]') \
      || die "tags fetch failed for $repo"
    if [ -z "$tag" ] || [ "$tag" = "null" ]; then
      echo '{}'
      exit 0
    fi
    name=$(jq -r '.name' <<<"$tag")
    sha=$(jq -r '.commit.sha' <<<"$tag")
    date=$(gh api "repos/${repo}/commits/${sha}" --jq '.commit.committer.date' 2>/dev/null) \
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
    gh api "repos/${repo}/compare/${old}...${new}" \
      --jq '{ahead: .ahead_by,
              commits: [.commits[] | {sha: .sha[0:7], author: .commit.author.name,
                                       date: .commit.author.date,
                                       message: (.commit.message | split("\n")[0])}],
              files: [.files[] | {filename, status, additions, deletions,
                                   has_patch: (.patch != null)}]}' \
      > "${out}-meta.json" \
      || die "compare meta failed for ${repo} ${old}...${new}"
    gh api "repos/${repo}/compare/${old}...${new}" \
      --jq '.files[] | .patch // empty' > "${out}.patch" \
      || die "compare patch failed for ${repo} ${old}...${new}"
    ;;

  *)
    die "unknown op: $op" 2
    ;;
esac
