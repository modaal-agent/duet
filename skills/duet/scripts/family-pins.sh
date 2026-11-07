#!/bin/bash
#
# family-pins.sh — the Duet family's newest releases, and a tree's pins checked against the
# exact-pin rule.
#
#   family-pins.sh latest                   # newest tag of each family repository (network)
#   family-pins.sh check [--latest] [<root>]  # the tree's pins; exit 1 on a disagreement
#
# `check` reads the tree only, and walks up from <root> (default: the working directory) to the
# directory holding parity/fixtures. It reads:
#   - every Package.swift (outside .build, .duet-family, DerivedData, checkouts): each
#     .package(url: …/modaal-agent/duet*.git, …) line
#   - every project.yml / xcodegen.yml: each package whose url names modaal-agent/duet*, and its
#     exactVersion / version / from / branch line
#   - every gradle/libs.versions.toml: the duet, duetServices and mocksProcessor keys
#   - parity/duet-tools.ref, and the manifest's mocks bundle:
# and fails when a family package is not pinned exactly, or when two pins of duet (or of
# duet-services) disagree. With --latest it also fetches the duet version the tree's duet-services
# release pins, fails when the tree pins a different duet, and prints each repository's newest tag.
#
# Runs under /bin/bash 3.2. Needs git and curl for `latest` and `check --latest` only.

set -eu

ORG=https://github.com/modaal-agent
RAW=https://raw.githubusercontent.com/modaal-agent

usage() {
  echo "usage: family-pins.sh latest | check [--latest] [<root>]" >&2
  exit 2
}

# The newest bare semver tag of a repository, or nothing.
newest_tag() {   # <repo> [<tag prefix>]
  git ls-remote --tags --refs "$ORG/$1.git" 2>/dev/null \
    | sed -n "s#.*refs/tags/${2:-}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\$#\1#p" \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

# The duet version a duet-services (or duet-migration) tag pins in its Package.swift.
pinned_duet_at() {   # <repo> <tag>
  curl -fsSL "$RAW/$1/$2/Package.swift" 2>/dev/null \
    | sed -n 's#.*modaal-agent/duet\.git", *exact: *"\([^"]*\)".*#\1#p' | head -1
}

newest_mocks_processor() {
  curl -fsSL https://modaal-agent.github.io/maven/dev/modaal/mocks-processor/maven-metadata.xml 2>/dev/null \
    | sed -n 's#.*<release>\(.*\)</release>.*#\1#p' | head -1
}

cmd_latest() {
  local repo tag
  for repo in duet duet-tools duet-services duet-macros duet-migration; do
    tag="$(newest_tag "$repo")"
    [ -n "$tag" ] || { echo "family-pins: no tag read from $ORG/$repo (network?)" >&2; exit 1; }
    case "$repo" in
      duet-services|duet-migration) echo "$repo $tag (pins duet $(pinned_duet_at "$repo" "$tag"))" ;;
      *) echo "$repo $tag" ;;
    esac
  done
  echo "swift-sourcery-templates bundle $(newest_tag swift-sourcery-templates templates-)"
  echo "mocks-processor $(newest_mocks_processor)"
}

# ── check ─────────────────────────────────────────────────────────

ROWS=""       # one "<name>|<version>|<kind>|<where>" per line
FAILURES=0

row() { ROWS="$ROWS$1|$2|$3|$4
"; }
fail() { echo "  ✗ $*"; FAILURES=$((FAILURES + 1)); }

find_root() {   # <start>
  local dir
  dir="$(cd "$1" && pwd)"
  while [ "$dir" != "/" ]; do
    [ -d "$dir/parity/fixtures" ] && { echo "$dir"; return; }
    dir="$(dirname "$dir")"
  done
  cd "$1" && pwd
}

tree_files() {   # <root> <name>...
  local root="$1"; shift
  local expr="" name
  for name in "$@"; do
    [ -z "$expr" ] && expr="-name $name" || expr="$expr -o -name $name"
  done
  # shellcheck disable=SC2086
  find "$root" \( -name .build -o -name .duet-family -o -name DerivedData -o -name checkouts \
    -o -name build -o -name .gradle -o -name .git -o -name node_modules \) -prune -o \
    \( $expr \) -type f -print 2>/dev/null | sort
}

package_name() {   # <url fragment> → duet | duet-services | duet-macros | duet-migration
  echo "$1" | sed -n 's#.*modaal-agent/\(duet[a-z-]*\).*#\1#p' | sed 's#\.git$##'
}

read_swift_manifests() {   # <root>
  local file rel n line name version kind
  while IFS= read -r file; do
    rel="${file#"$1"/}"
    while IFS= read -r line; do
      n="${line%%:*}"; line="${line#*:}"
      name="$(package_name "$line")"
      [ -n "$name" ] || continue
      version="$(echo "$line" | sed -nE 's#.*exact: *"([^"]*)".*#\1#p')"
      if [ -n "$version" ]; then
        kind=exact
      else
        kind="$(echo "$line" | sed -nE 's#.*(from|branch|revision|upToNextMajor|upToNextMinor):.*#\1#p')"
        version="$(echo "$line" | sed -nE 's#.*(from|branch|revision|upToNextMajor|upToNextMinor): *"([^"]*)".*#\2#p')"
        [ -n "$kind" ] || kind=range
      fi
      row "$name" "${version:-?}" "$kind" "$rel:$n"
    done < <(grep -n '\.package(' "$file" | grep 'modaal-agent/duet' || true)
  done < <(tree_files "$1" Package.swift)
}

read_xcodegen_specs() {   # <root>
  local file rel
  while IFS= read -r file; do
    rel="${file#"$1"/}"
    awk -v rel="$rel" '
      /url:.*modaal-agent\/duet/ {
        name = $0; sub(/.*modaal-agent\//, "", name); sub(/(\.git)?["'\'' ]*$/, "", name)
        pending = name; line = NR; next
      }
      pending != "" && /(exactVersion|version|from|minorVersion|majorVersion|branch|revision):/ {
        key = $1; sub(/:$/, "", key); value = $2; gsub(/["'\'']/, "", value)
        kind = (key == "exactVersion" || key == "version") ? "exact" : key
        print pending "|" value "|" kind "|" rel ":" line
        pending = ""
      }
      pending != "" && NR > line + 4 { print pending "|?|unpinned|" rel ":" line; pending = "" }
    ' "$file"
  done < <(tree_files "$1" project.yml xcodegen.yml)
}

read_catalogs() {   # <root>
  local file rel key value name
  while IFS= read -r file; do
    rel="${file#"$1"/}"
    for key in duet duetServices mocksProcessor; do
      value="$(grep -E "^$key[[:space:]]*=" "$file" | head -1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*$/\1/')"
      [ -n "$value" ] || continue
      case "$key" in
        duet) name=duet ;; duetServices) name=duet-services ;; mocksProcessor) name=mocks-processor ;;
      esac
      row "$name" "$value" exact "$rel"
    done
  done < <(tree_files "$1" libs.versions.toml)
}

distinct_versions() {   # <name> → the distinct versions pinned for it, one per line
  printf '%s' "$ROWS" | awk -F'|' -v n="$1" '$1 == n { print $2 }' | sort -u
}

cmd_check() {
  local latest=0 start=.
  while [ $# -gt 0 ]; do
    case "$1" in
      --latest) latest=1 ;;
      -*) usage ;;
      *) start="$1" ;;
    esac
    shift
  done
  [ -d "$start" ] || { echo "family-pins: $start is not a directory" >&2; exit 2; }
  local root
  root="$(find_root "$start")"
  echo "family-pins: $root"

  read_swift_manifests "$root"
  ROWS="$ROWS$(read_xcodegen_specs "$root")
"
  read_catalogs "$root"
  if [ -f "$root/parity/duet-tools.ref" ]; then
    row duet-tools "$(grep -vE '^[[:space:]]*(#|$)' "$root/parity/duet-tools.ref" | head -1 | tr -d '[:space:]')" \
      exact parity/duet-tools.ref
  fi
  if [ -f "$root/parity/manifest.yaml" ]; then
    local bundle
    bundle="$(grep -E '^[[:space:]]+bundle:' "$root/parity/manifest.yaml" | head -1 \
      | sed -E 's/.*bundle:[[:space:]]*//; s/[[:space:]]*(#.*)?$//')"
    [ -z "$bundle" ] || row mocks-bundle "$bundle" exact "parity/manifest.yaml (mocks.bundle)"
  fi
  ROWS="$(printf '%s' "$ROWS" | grep -v '^$' || true)
"

  if [ -z "$(printf '%s' "$ROWS" | tr -d '\n')" ]; then
    echo "family-pins: no family pin found under $root"
    return 0
  fi
  printf '%s' "$ROWS" | awk -F'|' '{ printf "  %-16s %-10s %-9s %s\n", $1, $2, $3, $4 }'

  printf '%s' "$ROWS" | awk -F'|' '$3 != "exact" { print $1 " is pinned " $3 " " $2 " at " $4 " — pin it exact" }' \
    | while IFS= read -r line; do echo "  ✗ $line"; done
  FAILURES=$((FAILURES + $(printf '%s' "$ROWS" | awk -F'|' '$3 != "exact"' | grep -c . || true)))

  local name versions
  for name in duet duet-services duet-tools; do
    versions="$(distinct_versions "$name")"
    if [ "$(printf '%s\n' "$versions" | grep -c .)" -gt 1 ]; then
      fail "$name is pinned at $(printf '%s' "$versions" | paste -sd, - | sed 's/,/, /g') — move every pin of it to one version in the same change"
    fi
  done

  if [ "$latest" = 1 ]; then
    local services duet want newest
    services="$(distinct_versions duet-services | head -1)"
    duet="$(distinct_versions duet | head -1)"
    if [ -n "$services" ] && [ -n "$duet" ]; then
      want="$(pinned_duet_at duet-services "$services")"
      if [ -z "$want" ]; then
        fail "could not read the duet pin of duet-services $services (network?)"
      elif [ "$want" != "$duet" ]; then
        fail "duet-services $services pins duet $want; the tree pins duet $duet — move both pins together"
      fi
    fi
    for name in duet duet-services duet-tools; do
      newest="$(newest_tag "$name")"
      [ -z "$newest" ] || echo "  newest $name: $newest"
    done
  fi

  if [ "$FAILURES" -gt 0 ]; then
    echo "family-pins: $FAILURES disagreement(s)"
    return 1
  fi
  echo "family-pins: OK"
}

[ $# -ge 1 ] || usage
case "$1" in
  latest) shift; [ $# -eq 0 ] || usage; cmd_latest ;;
  check) shift; cmd_check "$@" ;;
  *) usage ;;
esac
