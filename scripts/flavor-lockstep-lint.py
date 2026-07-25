#!/usr/bin/env python3
"""Flavor-lockstep linter for the framework's OWN contract surfaces (G4).

The adopter-repo lockstep-lint pins feature reducer twins; this lint applies the
same rail to the framework itself: the per-flavor residue (kernel, replay
adapter, shells, test support) is shape-twinned between `swift/` and `kotlin/`,
and a delta landing on one flavor without the other must fail CI — never drift
silently. Three checks:

  1. coverage — every production source file in either flavor is claimed by the
     twin map (`parity/flavor-parity.yaml`) exactly once, as half of a pair or
     as a declared single-flavor file (with a reason). A new file on one flavor
     is unmapped until the author says what it is.
  2. pair surface — for every pair, the public type and function names agree,
     modulo per-pair declared deltas (each with a reason). The declared deltas
     ARE the recorded per-flavor thinness — waiving is not free, it is the
     ledger entry.
  3. ledger freshness — `parity/flavor-parity-ledger.md` (LOC + open deltas per
     flavor, per surface) matches what `--write-ledger` would emit, so every
     release ships a current number, not a vibe.

Regex-level on purpose (the proven lockstep-lint.py pattern; swift-syntax/PSI
parsing is a later investment). Property/val surface is NOT compared at regex
level — scope-blind regexes over-capture locals and constructor params, so
types + functions are the tripwire and properties ride the type gate. Types and
functions compare as ONE case-folded name set per side: platform casing
(`EffectID`/`EffectId`) and DSL-word-as-type-vs-function idioms are not drift.
Two extractor accommodations keep the set honest: Kotlin function BODIES are
blanked before matching (local helper functions are not surface), and members
of `public protocol` blocks are extracted on Swift (protocol requirements carry
no access modifier but are public API — the mirror of Kotlin's interfaces).

Modes:
  (default)        run all three checks; exit 1 on any violation
  --write-ledger   regenerate parity/flavor-parity-ledger.md in place
  --dump           print each production file's extracted public surface
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = REPO_ROOT / "parity" / "flavor-parity.yaml"
LEDGER_PATH = REPO_ROOT / "parity" / "flavor-parity-ledger.md"

SWIFT_PRODUCTION_ROOT = "swift/Sources"
# Production source sets only: *Main + main. Framework tests (swift/Tests,
# src/test, src/jvmTest) are per-flavor receipts, outside the twin discipline.
KOTLIN_PRODUCTION_SETS = ("commonMain", "appleMain", "jvmMain", "main")

errors: list[str] = []


# ── twin map ────────────────────────────────────────────────────────────────


def parse_map(path: Path) -> dict:
    """Minimal parser for the map's fixed shape (no external yaml dependency)."""
    plan: dict = {"pairs": [], "singles": [], "excludes": []}
    section: str | None = None
    entry: dict | None = None
    sublist: str | None = None
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0:
            section = stripped[:-1] if stripped.endswith(":") else None
            entry = None
            sublist = None
            if section is not None and section not in plan:
                errors.append(f"[map] unknown top-level section: {section}")
            continue
        if section not in plan:
            continue
        if indent == 2 and stripped.startswith("- "):
            entry = {"deltas": []} if section == "pairs" else {}
            plan[section].append(entry)
            sublist = None
            stripped = stripped[2:].strip()
            indent = 4
        if entry is None:
            errors.append(f"[map] entry line outside a list item: {raw.strip()!r}")
            continue
        if indent == 4 and stripped == "deltas:":
            sublist = "deltas"
            continue
        if sublist == "deltas" and indent >= 6:
            if stripped.startswith("- "):
                entry["deltas"].append({})
                stripped = stripped[2:].strip()
            if entry["deltas"] and ":" in stripped:
                key, _, value = stripped.partition(":")
                entry["deltas"][-1][key.strip()] = value.strip()
            continue
        if indent == 4 and ":" in stripped:
            key, _, value = stripped.partition(":")
            entry[key.strip()] = value.strip()
            sublist = None
            continue
        errors.append(f"[map] unparseable line: {raw.strip()!r}")
    return plan


def check_map_shape(plan: dict) -> None:
    for pair in plan["pairs"]:
        for key in ("surface", "swift", "kotlin"):
            if key not in pair:
                errors.append(f"[map] pair missing `{key}:` — {pair}")
        for delta in pair.get("deltas", []):
            flavor = [k for k in ("swift", "kotlin") if k in delta]
            if len(flavor) != 1 or "reason" not in delta:
                errors.append(
                    f"[map] pair {pair.get('swift', '?')}: each delta needs exactly one"
                    f" of swift:/kotlin: (the symbol) plus reason: — {delta}")
    for single in plan["singles"]:
        for key in ("surface", "flavor", "file", "reason"):
            if key not in single:
                errors.append(f"[map] single missing `{key}:` — {single}")
    for exclude in plan["excludes"]:
        for key in ("prefix", "reason"):
            if key not in exclude:
                errors.append(f"[map] exclude missing `{key}:` — {exclude}")


# ── surface extraction ──────────────────────────────────────────────────────

SWIFT_ATTR = r"(?:@\w+(?:\([^)]*\))?\s+)*"
SWIFT_TYPE = re.compile(
    rf"^\s*{SWIFT_ATTR}public\b[^\n(]*?\b(?:class|struct|enum|protocol|actor|typealias)"
    rf"\s+(\w+)", re.M)
SWIFT_FUNC = re.compile(rf"^\s*{SWIFT_ATTR}public\b[^\n(]*?\bfunc\s+(\w+)", re.M)

KOTLIN_HIDDEN = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:private|internal|protected)\b")
KOTLIN_MODS = (
    r"(?:public\s+|abstract\s+|final\s+|open\s+|sealed\s+|data\s+|value\s+|inner\s+"
    r"|enum\s+|annotation\s+|actual\s+|expect\s+|external\s+)*")
KOTLIN_TYPE = re.compile(
    rf"^\s*(?:@\w+(?:\([^)]*\))?\s+)*{KOTLIN_MODS}(?:fun\s+interface|class|interface|object"
    rf"|typealias)\s+(\w+)", re.M)
KOTLIN_FUNC = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|suspend\s+|inline\s+|operator\s+|infix\s+"
    r"|open\s+|override\s+|actual\s+|expect\s+|external\s+|tailrec\s+)*fun\s+"
    r"(?!interface\b)(?:<[^>]*>\s+)?(?:[\w.<>?*, ]+\.)?(\w+)\s*[(<]", re.M)


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def blank_function_bodies(source: str) -> str:
    """Blanks the brace-delimited body of every `fun` (local functions are not
    surface) and of every private/internal type (their members are not surface
    either). A block opened by `fun interface` stays scannable — its members
    are interface requirements, i.e. surface. The lookback survives newlines
    while parentheses are open, so multi-line signatures classify correctly."""
    hidden_block = re.compile(
        r"\b(?:private|internal|protected)\b[^={]*\b(?:class|object|interface)\b")
    out: list[str] = []
    depth = 0
    parens = 0
    suppress_from: int | None = None
    lookback = ""
    for ch in source:
        if ch == "{":
            if suppress_from is None and (
                re.search(r"\bfun\s+(?!interface\b)", lookback) or hidden_block.search(lookback)
            ):
                suppress_from = depth
            depth += 1
            lookback = ""
        elif ch == "}":
            depth -= 1
            if suppress_from is not None and depth == suppress_from:
                suppress_from = None
                lookback = ""
                out.append("\n")
                continue
        elif ch == ";" or (ch == "\n" and parens == 0):
            lookback = ""
        else:
            if ch == "(":
                parens += 1
            elif ch == ")":
                parens = max(0, parens - 1)
            lookback += ch
        if suppress_from is None:
            out.append(ch)
        elif ch == "\n":
            out.append("\n")
    return "".join(out)


def swift_protocol_members(source: str) -> set[str]:
    """Requirements inside `public protocol` bodies carry no access modifier but
    are public API — extract them so protocol twins compare against Kotlin
    interfaces symmetrically."""
    members: set[str] = set()
    for match in re.finditer(rf"^\s*{SWIFT_ATTR}public\b[^\n]*?\bprotocol\s+\w+", source, re.M):
        start = source.find("{", match.end())
        if start < 0:
            continue
        depth = 0
        for i in range(start, len(source)):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    members |= set(re.findall(r"^\s*(?:static\s+|mutating\s+)*func\s+(\w+)",
                                              source[start:i], re.M))
                    break
    return members


def swift_surface(source: str) -> tuple[set[str], set[str]]:
    source = strip_comments(source)
    funcs = set(SWIFT_FUNC.findall(source)) | swift_protocol_members(source)
    return set(SWIFT_TYPE.findall(source)), funcs


def kotlin_surface(source: str) -> tuple[set[str], set[str]]:
    source = blank_function_bodies(strip_comments(source))
    lines = [l for l in source.splitlines() if not KOTLIN_HIDDEN.match(l)]
    visible = "\n".join(lines)
    return set(KOTLIN_TYPE.findall(visible)), set(KOTLIN_FUNC.findall(visible))


def surface(path: Path) -> tuple[set[str], set[str]]:
    source = path.read_text()
    return swift_surface(source) if path.suffix == ".swift" else kotlin_surface(source)


# ── production file discovery ───────────────────────────────────────────────


def production_files(plan: dict) -> tuple[list[str], list[str]]:
    excludes = [e["prefix"] for e in plan["excludes"]]

    def excluded(rel: str) -> bool:
        return any(rel.startswith(prefix) for prefix in excludes)

    swift = [
        str(p.relative_to(REPO_ROOT))
        for p in sorted((REPO_ROOT / SWIFT_PRODUCTION_ROOT).rglob("*.swift"))
    ]
    kotlin = [
        str(p.relative_to(REPO_ROOT))
        for p in sorted((REPO_ROOT / "kotlin").rglob("*.kt"))
        if "/build/" not in str(p)
        and any(f"/src/{s}/kotlin/" in str(p) for s in KOTLIN_PRODUCTION_SETS)
    ]
    return [f for f in swift if not excluded(f)], [f for f in kotlin if not excluded(f)]


# ── checks ──────────────────────────────────────────────────────────────────


def check_coverage(plan: dict, swift_files: list[str], kotlin_files: list[str]) -> None:
    claimed: dict[str, int] = {}
    for pair in plan["pairs"]:
        for key in ("swift", "kotlin"):
            if key in pair:
                claimed[pair[key]] = claimed.get(pair[key], 0) + 1
    for single in plan["singles"]:
        if "file" in single:
            claimed[single["file"]] = claimed.get(single["file"], 0) + 1

    for path, count in sorted(claimed.items()):
        if count > 1:
            errors.append(f"[coverage] {path}: claimed {count} times in the map")
        if not (REPO_ROOT / path).is_file():
            errors.append(f"[coverage] {path}: in the map but missing on disk")

    for path in swift_files + kotlin_files:
        if path not in claimed:
            errors.append(
                f"[coverage] {path}: production file not in parity/flavor-parity.yaml"
                " — pair it with its flavor twin, or declare it a single-flavor file"
                " with a reason")


def check_pairs(plan: dict) -> None:
    for pair in plan["pairs"]:
        swift_path = REPO_ROOT / pair.get("swift", "")
        kotlin_path = REPO_ROOT / pair.get("kotlin", "")
        if not swift_path.is_file() or not kotlin_path.is_file():
            continue  # coverage already reported it
        swift_types, swift_funcs = surface(swift_path)
        kotlin_types, kotlin_funcs = surface(kotlin_path)
        swift_set = {s.casefold() for s in swift_types | swift_funcs}
        kotlin_set = {s.casefold() for s in kotlin_types | kotlin_funcs}
        declared = {
            (side, delta[side].casefold())
            for delta in pair.get("deltas", [])
            for side in ("swift", "kotlin")
            if side in delta
        }
        label = f"{pair['swift']} ↔ {pair['kotlin']}"
        for ours, theirs, side, other in (
            (swift_set, kotlin_set, "swift", "kotlin"),
            (kotlin_set, swift_set, "kotlin", "swift"),
        ):
            for symbol in sorted(ours - theirs):
                if (side, symbol) not in declared:
                    errors.append(
                        f"[{label}] {side}-only symbol `{symbol}` — mirror it on the"
                        f" {other} flavor, or declare the delta (with a reason) in"
                        " parity/flavor-parity.yaml")
        for side, symbol in sorted(declared):
            ours, theirs = (swift_set, kotlin_set) if side == "swift" \
                else (kotlin_set, swift_set)
            if symbol not in ours or symbol in theirs:
                errors.append(
                    f"[{label}] stale delta: `{symbol}` is no longer {side}-only"
                    " — remove the entry from parity/flavor-parity.yaml")


# ── ledger ──────────────────────────────────────────────────────────────────


def render_ledger(plan: dict, swift_files: list[str], kotlin_files: list[str]) -> str:
    def loc(path: str) -> int:
        return len((REPO_ROOT / path).read_text().splitlines())

    surfaces: dict[str, dict] = {}
    for pair in plan["pairs"]:
        s = surfaces.setdefault(
            pair["surface"],
            {"swift": [], "kotlin": [], "pairs": 0, "singles": 0, "deltas": 0})
        s["swift"].append(pair["swift"])
        s["kotlin"].append(pair["kotlin"])
        s["pairs"] += 1
        s["deltas"] += len(pair.get("deltas", []))
    for single in plan["singles"]:
        s = surfaces.setdefault(
            single["surface"],
            {"swift": [], "kotlin": [], "pairs": 0, "singles": 0, "deltas": 0})
        s[single["flavor"]].append(single["file"])
        s["singles"] += 1

    lines = [
        "# Flavor-parity ledger",
        "",
        "<!-- GENERATED by scripts/flavor-lockstep-lint.py --write-ledger — do not",
        "edit by hand. The default lint run fails when this file is stale. -->",
        "",
        "Per-release measurement of the dual-flavor residue: LOC and open deltas per",
        "flavor, per contract surface. The revisit trigger fires on these numbers.",
        "LOC = raw line counts of production sources (tests excluded). Open deltas",
        "are the per-pair symbol waivers declared, with reasons, in",
        "`parity/flavor-parity.yaml`.",
        "",
        "| Surface | Pairs | Singles | Swift files | Swift LOC | Kotlin files | Kotlin LOC | Open deltas |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    totals = {"swift_files": 0, "swift_loc": 0, "kotlin_files": 0, "kotlin_loc": 0,
              "pairs": 0, "singles": 0, "deltas": 0}
    for name in sorted(surfaces):
        s = surfaces[name]
        swift_loc = sum(loc(f) for f in s["swift"])
        kotlin_loc = sum(loc(f) for f in s["kotlin"])
        lines.append(
            f"| {name} | {s['pairs']} | {s['singles']} | {len(s['swift'])} | {swift_loc}"
            f" | {len(s['kotlin'])} | {kotlin_loc} | {s['deltas']} |")
        totals["swift_files"] += len(s["swift"])
        totals["swift_loc"] += swift_loc
        totals["kotlin_files"] += len(s["kotlin"])
        totals["kotlin_loc"] += kotlin_loc
        totals["pairs"] += s["pairs"]
        totals["singles"] += s["singles"]
        totals["deltas"] += s["deltas"]
    lines.append(
        f"| **total** | {totals['pairs']} | {totals['singles']} | {totals['swift_files']}"
        f" | {totals['swift_loc']} | {totals['kotlin_files']} | {totals['kotlin_loc']}"
        f" | {totals['deltas']} |")

    lines += ["", "## Open deltas", "",
              "| Pair | Flavor | Symbol | Reason |", "| --- | --- | --- | --- |"]
    for pair in plan["pairs"]:
        for delta in pair.get("deltas", []):
            side = "swift" if "swift" in delta else "kotlin"
            lines.append(
                f"| {Path(pair['swift']).name} ↔ {Path(pair['kotlin']).name} | {side}"
                f" | `{delta[side]}` | {delta['reason']} |")

    lines += ["", "## Single-flavor files", "",
              "| Surface | Flavor | File | LOC | Reason |",
              "| --- | --- | --- | --- | --- |"]
    for single in plan["singles"]:
        lines.append(
            f"| {single['surface']} | {single['flavor']} | {single['file']}"
            f" | {loc(single['file'])} | {single['reason']} |")
    return "\n".join(lines) + "\n"


# ── entry ───────────────────────────────────────────────────────────────────


def main() -> int:
    if not MAP_PATH.is_file():
        print(f"flavor-lockstep-lint: missing {MAP_PATH.relative_to(REPO_ROOT)}")
        return 1
    plan = parse_map(MAP_PATH)
    check_map_shape(plan)
    swift_files, kotlin_files = production_files(plan)

    if "--dump" in sys.argv:
        for path in swift_files + kotlin_files:
            types, funcs = surface(REPO_ROOT / path)
            print(f"{path}")
            print(f"  types: {', '.join(sorted(types)) or '∅'}")
            print(f"  funcs: {', '.join(sorted(funcs)) or '∅'}")
        return 0

    check_coverage(plan, swift_files, kotlin_files)
    check_pairs(plan)

    ledger = render_ledger(plan, swift_files, kotlin_files)
    if "--write-ledger" in sys.argv:
        LEDGER_PATH.write_text(ledger)
        print(f"flavor-lockstep-lint: wrote {LEDGER_PATH.relative_to(REPO_ROOT)}")
    elif not LEDGER_PATH.is_file() or LEDGER_PATH.read_text() != ledger:
        errors.append(
            "[ledger] parity/flavor-parity-ledger.md is stale — run:"
            " python3 scripts/flavor-lockstep-lint.py --write-ledger")

    if errors:
        print("flavor-lockstep-lint: FAIL")
        for error in errors:
            print(f"  ✗ {error}")
        return 1
    pairs = len(plan["pairs"])
    singles = len(plan["singles"])
    deltas = sum(len(p.get("deltas", [])) for p in plan["pairs"])
    print(
        f"flavor-lockstep-lint: OK ({pairs} pair(s), {singles} single(s),"
        f" {deltas} open delta(s), {len(swift_files)}+{len(kotlin_files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
