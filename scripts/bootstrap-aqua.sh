#!/bin/bash
#
# Bootstrap aqua by downloading the official release tarball and verifying its
# SHA256 against the value pinned below. Idempotent: skips download if aqua is
# already installed at the expected location.
#
# When bumping AQUA_VERSION, fetch the new SHA256 from the release's
# checksums.txt (Cosign-signed at the upstream).
#
# After bootstrap, generates aqua-checksums.json on first run (Trust on First
# Use), then runs `aqua install -a` against $HOME/dotfiles/aqua.yaml.

set -euo pipefail

AQUA_VERSION=v2.57.1
AQUA_DARWIN_ARM64_SHA256=81f908c93263ba83bc06ba81d75e2594390b676ea131bb3f7691a0d4575948e4

aqua_root="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}"
aqua_bin="$aqua_root/bin/aqua"

if [ ! -x "$aqua_bin" ]; then
  # aqua.yaml's supported_envs is darwin/arm64-only, so bootstrap matches that scope.
  case "$(uname -sm)" in
    "Darwin arm64") expected=$AQUA_DARWIN_ARM64_SHA256 ;;
    *) echo "aqua bootstrap: unsupported platform $(uname -sm) (arm64 darwin only)" >&2; exit 1 ;;
  esac

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  tarball="aqua_darwin_arm64.tar.gz"
  url="https://github.com/aquaproj/aqua/releases/download/${AQUA_VERSION}/${tarball}"

  echo "aqua bootstrap: downloading ${url}"
  curl -sSfL "$url" -o "${tmp}/${tarball}"

  actual=$(shasum -a 256 "${tmp}/${tarball}" | awk '{print $1}')
  if [ "$actual" != "$expected" ]; then
    echo "aqua bootstrap: SHA256 mismatch" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$aqua_bin")"
  tar -xzf "${tmp}/${tarball}" -C "$tmp" aqua
  install -m 755 "${tmp}/aqua" "$aqua_bin"
  echo "aqua bootstrap: installed $($aqua_bin -v)"
fi

export AQUA_GLOBAL_CONFIG="$HOME/dotfiles/aqua.yaml"
if [ ! -f "$HOME/dotfiles/aqua-checksums.json" ]; then
  echo "aqua: aqua-checksums.json missing, generating (Trust on First Use)"
  "$aqua_bin" update-checksum -a
  echo "aqua: → review and commit aqua-checksums.json after this run"
fi

"$aqua_bin" install -a
