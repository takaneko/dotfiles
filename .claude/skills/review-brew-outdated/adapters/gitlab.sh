#!/usr/bin/env bash
# GitLab adapter (works against any GitLab instance).
#
# Usage:
#   gitlab.sh resolve-tag <host> <project_path> <version>
#   gitlab.sh fetch-diff  <host> <project_path> <old_ref> <new_ref> <out_prefix>
#
# <host> examples: gitlab.inria.fr, code.videolan.org, salsa.debian.org
# <project_path> is the namespace/name form with literal slashes (e.g. "mpc/mpc");
# this script URL-encodes it before passing to the API.

set -euo pipefail

die() { echo "gitlab.sh: $*" >&2; exit "${2:-3}"; }

# URL-encode slashes in the project path. Homebrew-derived project paths are
# plain [a-zA-Z0-9._/-], so only '/' needs replacing.
urlenc_path() { printf '%s' "$1" | sed 's|/|%2F|g'; }

op=${1:?op}; shift

case "$op" in
  resolve-tag)
    host=${1:?host}; project=${2:?project_path}; version=${3:?version}
    enc=$(urlenc_path "$project")
    curl -sSf --max-time 30 \
      "https://${host}/api/v4/projects/${enc}/repository/tags?per_page=100" \
      | jq --arg v "$version" \
          '[.[] | select(.name | contains($v))] | .[0]
           | if . == null then {}
             else {name: .name, sha: .commit.id, date: .commit.committed_date} end' \
      || die "tags fetch failed for ${host}/${project}"
    ;;

  fetch-diff)
    host=${1:?host}; project=${2:?project_path}
    old=${3:?old_ref}; new=${4:?new_ref}; out=${5:?out_prefix}
    enc=$(urlenc_path "$project")
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    curl -sSf --max-time 60 \
      "https://${host}/api/v4/projects/${enc}/repository/compare?from=${old}&to=${new}" \
      > "$tmp" \
      || die "compare fetch failed for ${host}/${project} ${old}..${new}"
    jq '{commits: [.commits[] | {sha: .short_id, author: .author_name,
                                  date: .committed_date, message: .title}],
         files: [.diffs[] | {filename: .new_path,
                              status: (if .new_file then "added"
                                        elif .deleted_file then "removed"
                                        else "modified" end)}]}' \
      "$tmp" > "${out}-meta.json"
    jq -r '.diffs[].diff' "$tmp" > "${out}.patch"
    ;;

  *)
    die "unknown op: $op" 2
    ;;
esac
