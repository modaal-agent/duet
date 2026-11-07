#!/bin/bash
#
# duet-cli.sh — runs the Duet toolchain CLI (`duet`, from github.com/modaal-agent/duet-tools) at
# the tree's pin.
#
#   duet-cli.sh [--ref <tag>] <verb> [args…]     # e.g. duet-cli.sh verify --feature splash
#   duet-cli.sh [--ref <tag>] --print-path       # print the binary it would run, run nothing
#
# Resolution, first match wins:
#   1. the tree's own tools/duet wrapper (the tree is found by walking up to parity/fixtures);
#      --ref reaches it as DUET_TOOLS_REF
#   2. $DUET_BIN
#   3. `duet` on PATH, when `duet version` prints the pin
#   4. a binary already cached for the pin: the tree's .duet-family/duet-bin/<pin>/duet, or this
#      script's cache
#   5. the release asset for the pin — duet-macos-arm64.zip and its .sha256 from the duet-tools
#      GitHub release, checksum-verified (macOS on Apple silicon only)
#   6. `duet` on PATH at another version, with a warning naming both versions
# and otherwise it prints the from-source build command and exits 2.
#
# The pin: --ref, else the tree's parity/duet-tools.ref, else the newest duet-tools release tag.
# DUET_CLI_RELEASE_BASE replaces the release download base, a mirror (or a file:// directory)
# holding <pin>/duet-macos-arm64.zip and its .sha256.
# The cache: $DUET_CACHE, else $HOME/.cache/duet when writable, else ${TMPDIR:-/tmp}/duet-cli.
# An agent sandbox may refuse $HOME/.cache and the network; the download needs github.com and
# release-assets.githubusercontent.com.
#
# Runs under /bin/bash 3.2. Needs git (only when no pin is written down), curl, shasum and unzip
# (only for the download).

set -eu

REPO=https://github.com/modaal-agent/duet-tools
ASSET=duet-macos-arm64.zip

say() { echo "duet-cli: $*" >&2; }

REF=""
PRINT_PATH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || { say "--ref needs a tag"; exit 2; }; REF="$2"; shift 2 ;;
    --ref=*) REF="${1#--ref=}"; shift ;;
    --print-path) PRINT_PATH=1; shift ;;
    *) break ;;
  esac
done
if [ "$PRINT_PATH" = 0 ] && [ $# -eq 0 ]; then
  echo "usage: duet-cli.sh [--ref <tag>] <verb> [args…] | [--ref <tag>] --print-path" >&2
  exit 2
fi

run() {   # <binary> <argument>… — run the binary with the arguments, or print its path
  local binary="$1"; shift
  if [ "$PRINT_PATH" = 1 ]; then echo "$binary"; exit 0; fi
  exec "$binary" "$@"
}

ROOT=""
dir="$(pwd)"
while [ "$dir" != "/" ]; do
  if [ -d "$dir/parity/fixtures" ]; then ROOT="$dir"; break; fi
  dir="$(dirname "$dir")"
done

# 1. The tree's wrapper owns its pin and its own cache.
if [ -n "$ROOT" ] && [ -x "$ROOT/tools/duet" ] && [ "$PRINT_PATH" = 0 ]; then
  if [ -n "$REF" ]; then export DUET_TOOLS_REF="$REF"; fi
  exec "$ROOT/tools/duet" "$@"
fi

# 2. An explicit binary.
if [ -n "${DUET_BIN:-}" ]; then
  [ -x "$DUET_BIN" ] || { say "DUET_BIN=$DUET_BIN is not executable"; exit 1; }
  run "$DUET_BIN" "$@"
fi

TAG="$REF"
if [ -z "$TAG" ] && [ -n "$ROOT" ] && [ -f "$ROOT/parity/duet-tools.ref" ]; then
  TAG="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/parity/duet-tools.ref" | head -1 | tr -d '[:space:]')"
fi
if [ -z "$TAG" ]; then
  TAG="$(git ls-remote --tags --refs "$REPO.git" 2>/dev/null \
    | sed -n 's#.*refs/tags/\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$#\1#p' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)"
  [ -n "$TAG" ] || { say "no pin: the tree has no parity/duet-tools.ref and $REPO could not be read — run it with --ref <tag>"; exit 1; }
fi

path_version() { "$1" version 2>/dev/null | sed -n 's/^duet \([^ ]*\).*/\1/p' | head -1; }

# 3. `duet` on PATH at the pin.
ON_PATH="$(command -v duet 2>/dev/null || true)"
if [ -n "$ON_PATH" ] && [ "$(path_version "$ON_PATH")" = "$TAG" ]; then
  run "$ON_PATH" "$@"
fi

# 4. A binary already cached for the pin. CACHE is where step 5 writes.
if [ -n "${DUET_CACHE:-}" ]; then
  CACHE="$DUET_CACHE"
elif mkdir -p "$HOME/.cache/duet" 2>/dev/null && [ -w "$HOME/.cache/duet" ]; then
  CACHE="$HOME/.cache/duet"
else
  CACHE="${TMPDIR:-/tmp}"; CACHE="${CACHE%/}/duet-cli"
fi
# Every cache location is read: a sandbox that refuses writes to $HOME/.cache still reads it, so a
# binary fetched outside the sandbox is found from inside it.
TMP_CACHE="${TMPDIR:-/tmp}"; TMP_CACHE="${TMP_CACHE%/}/duet-cli"
for candidate in ${ROOT:+"$ROOT/.duet-family/duet-bin/$TAG/duet"} ${DUET_CACHE:+"$DUET_CACHE/$TAG/duet"} \
    "$HOME/.cache/duet/$TAG/duet" "$TMP_CACHE/$TAG/duet"; do
  if [ -x "$candidate" ] && [ "$(path_version "$candidate")" = "$TAG" ]; then
    run "$candidate" "$@"
  fi
done

from_source() {
  say "build it from source instead (needs a Swift toolchain, takes minutes):"
  say "  git clone --branch $TAG --depth 1 $REPO && (cd duet-tools && swift build -c release)"
  say "then run it with DUET_BIN=\$PWD/duet-tools/.build/release/duet"
}

# 5. The release asset.
if [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]; then
  DEST="$CACHE/$TAG"
  if mkdir -p "$DEST" 2>/dev/null && [ -w "$DEST" ]; then
    BASE="${DUET_CLI_RELEASE_BASE:-$REPO/releases/download}/$TAG"
    say "downloading $BASE/$ASSET"
    # The checksum file first: a 404 there means the tag has no release asset, and no response
    # at all means no network.
    status="$(curl -sSL -o "$DEST/$ASSET.sha256" -w '%{http_code}' "$BASE/$ASSET.sha256" 2>/dev/null || true)"
    case "$status" in
      200|000) ;;
      *) rm -f "$DEST/$ASSET.sha256"
         say "$BASE/$ASSET.sha256 answered HTTP $status: $TAG has no release asset — check the tag in parity/duet-tools.ref or --ref"
         status=missing ;;
    esac
    if [ "$status" = missing ]; then
      :
    elif [ -s "$DEST/$ASSET.sha256" ] && curl -fsSL -o "$DEST/$ASSET" "$BASE/$ASSET"; then
      want="$(awk 'NR == 1 { print $1 }' "$DEST/$ASSET.sha256")"
      got="$(shasum -a 256 "$DEST/$ASSET" | awk '{ print $1 }')"
      if [ -z "$want" ] || [ "$want" != "$got" ]; then
        rm -f "$DEST/$ASSET" "$DEST/$ASSET.sha256"
        say "checksum mismatch for $TAG ($ASSET: $got, .sha256: ${want:-empty}) — nothing was run"
        exit 1
      fi
      unzip -oq "$DEST/$ASSET" -d "$DEST"
      rm -f "$DEST/$ASSET"
      chmod +x "$DEST/duet"
      say "duet $TAG cached at $DEST/duet (checksum verified)"
      run "$DEST/duet" "$@"
    else
      rm -f "$DEST/$ASSET" "$DEST/$ASSET.sha256"
      say "the download failed. It needs network access to github.com and release-assets.githubusercontent.com;"
      say "inside an agent sandbox, ask the user to allow both hosts, or to run this once outside it:"
      say "  \"$0\" --ref $TAG version"
    fi
  else
    say "no writable cache directory (tried $DEST); set DUET_CACHE to a writable directory"
  fi
else
  say "the release ships a macOS Apple-silicon binary only ($(uname -s) $(uname -m) here)"
fi

# 6. `duet` on PATH at another version.
if [ -n "$ON_PATH" ]; then
  say "running $ON_PATH ($(path_version "$ON_PATH" || true)); the pin is $TAG — results can differ from the pinned toolchain's"
  run "$ON_PATH" "$@"
fi

from_source
exit 2
