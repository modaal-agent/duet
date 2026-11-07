#!/bin/bash
#
# test-skill-scripts.sh — offline tests of skills/duet/scripts/duet-cli.sh and family-pins.sh.
#
#   scripts/test-skill-scripts.sh
#
# No network: every download goes to a file:// mirror (DUET_CLI_RELEASE_BASE), every pin is
# written down, and HOME points into a temporary directory. The download cases run on macOS on
# Apple silicon only, where the release asset exists; elsewhere they are reported skipped.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/skills/duet/scripts/duet-cli.sh"
PINS="$ROOT/skills/duet/scripts/family-pins.sh"
TMP_BASE="${TMPDIR:-/tmp}"
WORK="$(cd "$(mktemp -d "${TMP_BASE%/}/duet-skill-scripts.XXXXXX")" && pwd)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
skipped=0

# expect <name> <exit status> <text the output must contain> -- <command…>
expect() {
  local name="$1" want_status="$2" want_text="$3"; shift 4
  local out status
  out="$("$@" 2>&1)"; status=$?
  if [ "$status" = "$want_status" ] && printf '%s' "$out" | grep -qF -- "$want_text"; then
    passed=$((passed + 1)); echo "ok    $name"
  else
    failed=$((failed + 1)); echo "FAIL  $name (exit $status, want $want_status; want text: $want_text)"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

skip() { skipped=$((skipped + 1)); echo "skip  $1"; }

fake_duet() {   # <path> <version> — a stand-in binary printing `duet <version>`
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\nif [ "$1" = version ]; then echo "duet %s"; else echo "fake duet %s ran: $*"; fi\n' "$2" "$2" > "$1"
  chmod +x "$1"
}

tree() {   # <dir> — an empty Duet tree root
  mkdir -p "$1/parity/fixtures"
}

export HOME="$WORK/home"
mkdir -p "$HOME"
unset DUET_BIN DUET_CACHE DUET_TOOLS_REF
export DUET_CLI_RELEASE_BASE="file://$WORK/mirror"
PATH_NO_DUET="/usr/bin:/bin:/usr/sbin:/sbin"

# ── family-pins.sh check ──────────────────────────────────────────

T="$WORK/pins-good"; tree "$T"
mkdir -p "$T/src-ios/App" "$T/src-kmp/gradle"
cat > "$T/src-ios/App/Package.swift" <<'EOF'
    .package(url: "https://github.com/modaal-agent/duet.git", exact: "1.2.3"),
    .package(url: "https://github.com/modaal-agent/duet-services.git", exact: "4.5.6"),
EOF
printf 'duet = "1.2.3"\nduetServices = "4.5.6"\n' > "$T/src-kmp/gradle/libs.versions.toml"
printf '# the pin\n7.8.9\n' > "$T/parity/duet-tools.ref"
printf 'packages:\n  Duet:\n    url: https://github.com/modaal-agent/duet\n    exactVersion: 1.2.3\n' > "$T/src-ios/App/project.yml"
expect "pins: agreeing exact pins pass" 0 "family-pins: OK" -- /bin/bash "$PINS" check "$T"
expect "pins: the walk up finds the root" 0 "duet-tools       7.8.9" -- /bin/bash -c "cd '$T/src-ios/App' && /bin/bash '$PINS' check"
expect "pins: an XcodeGen exactVersion is read" 0 "src-ios/App/project.yml:3" -- /bin/bash "$PINS" check "$T"

T="$WORK/pins-from"; tree "$T"; mkdir -p "$T/App"
printf '.package(url: "https://github.com/modaal-agent/duet.git", from: "1.2.3"),\n' > "$T/App/Package.swift"
expect "pins: a from: pin fails" 1 "duet is pinned from 1.2.3 at App/Package.swift:1 — pin it exact" -- /bin/bash "$PINS" check "$T"

T="$WORK/pins-split"; tree "$T"; mkdir -p "$T/App" "$T/gradle"
printf '.package(url: "https://github.com/modaal-agent/duet.git", exact: "1.2.3"),\n' > "$T/App/Package.swift"
printf 'duet = "1.2.4"\n' > "$T/gradle/libs.versions.toml"
expect "pins: two duet versions fail" 1 "duet is pinned at 1.2.3, 1.2.4" -- /bin/bash "$PINS" check "$T"

T="$WORK/pins-none"; tree "$T"
expect "pins: a tree with no pin passes" 0 "no family pin found" -- /bin/bash "$PINS" check "$T"
expect "pins: an unknown command is a usage error" 2 "usage:" -- /bin/bash "$PINS" nonsense

# ── duet-cli.sh ───────────────────────────────────────────────────

T="$WORK/cli-wrapper"; tree "$T"; mkdir -p "$T/tools"
printf '#!/bin/sh\necho "wrapper ref=${DUET_TOOLS_REF:-none} args=$*"\n' > "$T/tools/duet"; chmod +x "$T/tools/duet"
expect "cli: the tree's tools/duet runs" 0 "wrapper ref=none args=lint" -- /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"
expect "cli: --ref reaches the wrapper" 0 "wrapper ref=9.0.0 args=verify --feature a" -- /bin/bash -c "cd '$T' && /bin/bash '$CLI' --ref 9.0.0 verify --feature a"

fake_duet "$WORK/bin/duet" 3.0.0
expect "cli: DUET_BIN runs with the arguments" 0 "fake duet 3.0.0 ran: verify --feature a" -- env DUET_BIN="$WORK/bin/duet" /bin/bash "$CLI" verify --feature a

T="$WORK/cli-cached"; tree "$T"; printf '2.0.0\n' > "$T/parity/duet-tools.ref"
fake_duet "$WORK/cache/2.0.0/duet" 2.0.0
expect "cli: a binary cached for the pin runs" 0 "fake duet 2.0.0 ran: lint" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"
expect "cli: --print-path prints the cached binary" 0 "$WORK/cache/2.0.0/duet" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' --print-path"
fake_duet "$T/.duet-family/duet-bin/2.0.0/duet" 2.0.0
expect "cli: the tree's .duet-family cache is read first" 0 "$T/.duet-family/duet-bin/2.0.0/duet" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' --print-path"

T="$WORK/cli-pathpin"; tree "$T"; printf '3.0.0\n' > "$T/parity/duet-tools.ref"
expect "cli: duet on PATH at the pin runs" 0 "fake duet 3.0.0 ran: lint" -- env PATH="$WORK/bin:$PATH_NO_DUET" DUET_CACHE="$WORK/empty-cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"

T="$WORK/cli-miss"; tree "$T"; printf '5.0.0\n' > "$T/parity/duet-tools.ref"
expect "cli: duet on PATH at another version runs with a warning" 0 "the pin is 5.0.0" -- env PATH="$WORK/bin:$PATH_NO_DUET" DUET_CACHE="$WORK/empty-cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"
expect "cli: no binary at all prints the source build and exits 2" 2 "git clone --branch 5.0.0" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/empty-cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"

if [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]; then
  mkdir -p "$WORK/mirror/6.0.0" "$WORK/zip"
  fake_duet "$WORK/zip/duet" 6.0.0
  (cd "$WORK/zip" && zip -q "$WORK/mirror/6.0.0/duet-macos-arm64.zip" duet)
  (cd "$WORK/mirror/6.0.0" && shasum -a 256 duet-macos-arm64.zip > duet-macos-arm64.zip.sha256)
  T="$WORK/cli-download"; tree "$T"; printf '6.0.0\n' > "$T/parity/duet-tools.ref"
  expect "cli: the release asset is downloaded, verified and run" 0 "fake duet 6.0.0 ran: lint" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/dl-cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"
  expect "cli: the second run uses the cache" 0 "$WORK/dl-cache/6.0.0/duet" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/dl-cache" DUET_CLI_RELEASE_BASE="file:///nonexistent" /bin/bash -c "cd '$T' && /bin/bash '$CLI' --print-path"
  echo "0000  duet-macos-arm64.zip" > "$WORK/mirror/6.0.0/duet-macos-arm64.zip.sha256"
  expect "cli: a checksum mismatch runs nothing and exits 1" 1 "checksum mismatch for 6.0.0" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/dl-cache-2" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"
  expect "cli: no mirror names the hosts the download needs" 2 "release-assets.githubusercontent.com" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/dl-cache-3" DUET_CLI_RELEASE_BASE="file:///nonexistent" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"
else
  skip "cli: the release asset is downloaded, verified and run (macOS arm64 only)"
  skip "cli: a checksum mismatch runs nothing (macOS arm64 only)"
  T="$WORK/cli-linux"; tree "$T"; printf '6.0.0\n' > "$T/parity/duet-tools.ref"
  expect "cli: another host is told the binary is macOS-only" 2 "macOS Apple-silicon binary only" -- env PATH="$PATH_NO_DUET" DUET_CACHE="$WORK/dl-cache" /bin/bash -c "cd '$T' && /bin/bash '$CLI' lint"
fi

echo "test-skill-scripts: $passed passed, $failed failed, $skipped skipped"
[ "$failed" = 0 ]
