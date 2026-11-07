#!/bin/bash
#
# check-skill.sh — the gate for the agent skill in skills/duet/, the marketplace manifest in
# .claude-plugin/ and the plugin manifest in skills/.claude-plugin/.
#
#   scripts/check-skill.sh                     # every check; C10–C12 clone duet-tools and
#                                              # duet-services from GitHub into a temporary directory
#   scripts/check-skill.sh --offline           # C10–C12 skipped
#   scripts/check-skill.sh --tools-dir <git checkout> --services-dir <git checkout>
#                                              # C10–C12 read local clones (their tags) instead
#   scripts/check-skill.sh --self-test         # seeds one violation per check in a scratch tree
#                                              # and fails unless each check goes red
#
# The checks:
#   C1  SKILL.md's frontmatter parses: `---` on line 1, one `key: value` per line, a closing `---`,
#       no unquoted value holding ": "
#   C2  `name:` equals the skill's directory name
#   C3  the frontmatter keys are among name, description, license, compatibility, metadata,
#       allowed-tools
#   C4  `description` is 1–1,024 characters
#   C5  SKILL.md and each reference are at most 250 lines
#   C6  every relative link resolves to a file inside skills/duet/
#   C7  every Duet product, Kotlin artifact and type the skill names in code exists in this
#       repository or in duet-services
#   C8  every framework symbol on SYMBOLS that the skill names in code is declared in swift/Sources
#       or kotlin/*/src
#   C9  no version literal (N.N.N) anywhere under skills/duet/
#   C10 every duet verb and duet_* MCP tool the skill names exists at duet-tools' newest tag
#   C11 every diagnostic the skill quotes (a heading's code span in troubleshooting.md, the first
#       column of an Output, Diagnostic, finding or text table) appears in duet-tools' sources (any
#       tag; a note when the newest tag lacks it) or in this repository's runners
#   C12 every duet-services product, artifact and symbol on SERVICES_SYMBOLS the skill names exists
#       at duet-services' newest tag
#   C13 every command in a fenced shell block starts with an allowed command or the tree's scripts/
#   C14 the marketplace's one entry and its source's .claude-plugin/plugin.json parse and agree on
#       the name; the plugin loads skills/duet/; `icon` is a file in the plugin; `version` is
#       MAJOR.MINOR.PATCH, and nothing under the plugin's root changed since the commit that set it
#       (needs the full git history; a note without it); every evals/<case>/ holds prompt.md and a
#       grader of a known type; the skill's scripts pass `bash -n`
#
# Exit status: 0 when every check passes, 1 when one fails, 2 on a usage or setup error.
# Needs bash, git and python3.

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$ROOT" "$@" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

TOOLS_URL = "https://github.com/modaal-agent/duet-tools"
SERVICES_URL = "https://github.com/modaal-agent/duet-services"

STANDARD_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}

# C8: framework symbols the skill may name. A symbol named in code must be declared in this
# repository's swift/Sources or kotlin/*/src. Add a symbol here when the skill starts naming it.
SYMBOLS = [
    "Store", "TestStore", "Reducer", "Effect", "EffectPayload", "Runtime",
    "StoreHost", "ViewShell", "ChildStores", "ChildSlot", "ProjectionJoin", "Relay",
    "AnyActionHandler", "RetainedRoot", "RouteSpineCodec", "Working", "WorkerTester",
    "ScenarioRunner", "ChainScenarioRunner", "ChainNode", "FixtureRunner", "TestClock",
    "KernelClock", "CanonicalSumCodable", "verifyOrRecord", "whenAction", "thenEffects",
]

# C12: duet-services symbols the skill may name, declared in duet-services at its newest tag.
SERVICES_SYMBOLS = [
    "AnalyticsTrackingWorker", "Themeable", "ThemeDefaulting",
]

# C13: a command in a fenced shell block starts with one of these, or with a path into the tree's
# own scripts.
ALLOWED_COMMANDS = [
    "tools/duet", "duet", "./gradlew", "cd", "swift", "xcodebuild", "xcodegen", "xcrun", "adb",
    "git", "curl", "shasum", "unzip", "python3", "gh", "for",
]
ALLOWED_PREFIXES = ['"${CLAUDE_SKILL_DIR}/scripts/', "scripts/", "./scripts/", "parity/scripts/"]
SHELL_LANGS = {"bash", "sh", "shell", "zsh", "console"}

GRADER_TYPES = {"llm", "regex", "tool_used"}

# C11: a table whose first header cell is one of these quotes CLI output in its first column.
DIAGNOSTIC_HEADERS = {"output", "diagnostic", "finding", "text"}

LINE_BUDGET = 250
DESCRIPTION_BUDGET = 1024


# ── reading ─────────────────────────────────────────────────────────

def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def files_under(top, suffixes, skip_parts=("build", "Tests")):
    """Source files under top, without build outputs and test source sets (Tests/, src/test,
    src/jvmTest, …)."""
    out = []
    for dirpath, dirnames, filenames in os.walk(top):
        in_src = os.path.basename(dirpath) == "src"
        dirnames[:] = sorted(d for d in dirnames
                             if d not in skip_parts and not d.startswith(".")
                             and not (in_src and (d == "test" or d.endswith("Test"))))
        for name in sorted(filenames):
            if name.endswith(suffixes):
                out.append(os.path.join(dirpath, name))
    return out


def source_corpus(top, subdirs, suffixes=(".swift", ".kt")):
    texts = []
    for sub in subdirs:
        base = os.path.join(top, sub)
        if os.path.isdir(base):
            texts.extend(read(f) for f in files_under(base, suffixes))
    return "\n".join(texts)


class GitTree:
    """A git clone read at its tags, without a checkout."""

    def __init__(self, path):
        self.path = path

    def git(self, *args):
        return subprocess.run(["git", "-C", self.path, *args], check=True,
                              capture_output=True, text=True).stdout

    def tags(self):
        found = []
        for tag in self.git("tag", "--list").split():
            match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", tag)
            if match:
                found.append((tuple(int(x) for x in match.groups()), tag))
        return [tag for _, tag in sorted(found, reverse=True)]

    def files(self, tag, prefix, suffixes):
        pathspec = ["--", prefix] if prefix else []
        names = [n for n in self.git("ls-tree", "-r", "--name-only", tag, *pathspec).splitlines()
                 if n.endswith(suffixes) and "/Tests/" not in n and "/src/test/" not in n]
        if not names:
            return {}
        batch = subprocess.run(["git", "-C", self.path, "cat-file", "--batch"],
                               input="".join(f"{tag}:{n}\n" for n in names).encode(),
                               check=True, capture_output=True).stdout
        out, offset = {}, 0
        for name in names:
            header_end = batch.index(b"\n", offset)
            size = int(batch[offset:header_end].split()[2])
            start = header_end + 1
            out[name] = batch[start:start + size].decode("utf-8", "replace")
            offset = start + size + 1
        return out

    def text(self, tag, path):
        try:
            return self.git("show", f"{tag}:{path}")
        except subprocess.CalledProcessError:
            return ""


def clone(url, into):
    subprocess.run(["git", "clone", "--quiet", "--no-checkout", url, into], check=True,
                   capture_output=True, text=True)
    return GitTree(into)


# ── markdown ────────────────────────────────────────────────────────

FENCE = re.compile(r"^\s*(```+|~~~+)\s*([A-Za-z0-9_+-]*)")
SPAN = re.compile(r"(`+)(.+?)\1")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


class Markdown:
    def __init__(self, path, rel):
        self.path, self.rel = path, rel
        self.text = read(path)
        self.lines = self.text.split("\n")
        self.body_start = 0
        if self.lines and self.lines[0] == "---":
            for i in range(1, len(self.lines)):
                if self.lines[i] == "---":
                    self.body_start = i + 1
                    break

    def walk(self):
        """(line number, line, fence language or None) for every body line outside fence markers."""
        fence = None
        for index in range(self.body_start, len(self.lines)):
            line = self.lines[index]
            match = FENCE.match(line)
            if match:
                if fence is None:
                    fence = (match.group(1)[0] * 3, match.group(2).lower())
                    continue
                if line.strip().startswith(fence[0]) and not line.strip().strip(fence[0][0]):
                    fence = None
                    continue
            yield index + 1, line, (fence[1] if fence else None)

    def spans(self):
        for number, line, lang in self.walk():
            if lang is None:
                for match in SPAN.finditer(line):
                    yield number, match.group(2).strip().replace("\\|", "|")

    def code(self):
        """Every code span and every fenced line: (line number, text)."""
        for number, line, lang in self.walk():
            if lang is None:
                for match in SPAN.finditer(line):
                    yield number, match.group(2).replace("\\|", "|")
            elif lang in SHELL_LANGS:
                yield number, re.sub(r"(^|\s)#.*$", "", line)
            else:
                yield number, line

    def tables(self):
        """(header cells, [(line number, cells)]) for every pipe table outside fences."""
        rows, header = [], None
        for number, line, lang in list(self.walk()) + [(0, "", None)]:
            stripped = line.strip()
            if lang is None and stripped.startswith("|"):
                cells = [c.strip() for c in re.split(r"(?<!\\)\|", stripped.strip("|"))]
                if header is None:
                    header = cells
                elif not all(re.fullmatch(r":?-+:?", c) for c in cells):
                    rows.append((number, cells))
                continue
            if header is not None:
                yield header, rows
            rows, header = [], None


def frontmatter(md, report):
    lines = md.lines
    if not lines or lines[0] != "---":
        report.fail("C1", f"{md.rel}:1: the file does not start with ---")
        return {}
    if md.body_start == 0:
        report.fail("C1", f"{md.rel}: no closing --- for the frontmatter")
        return {}
    keys, current = {}, None
    index = 1
    while index < md.body_start - 1:
        line, number = lines[index], index + 1
        index += 1
        if not line.strip():
            continue
        if line[0] in " \t":
            if current is None:
                report.fail("C1", f"{md.rel}:{number}: an indented line before any key")
                continue
            nested = re.match(r"^\s+([A-Za-z0-9_-]+):(?:\s+(.*))?$", line)
            if nested:
                check_value(md, number, nested.group(2) or "", report)
            continue
        match = re.match(r"^([A-Za-z0-9_-]+):(?:\s+(.*))?$", line)
        if not match:
            report.fail("C1", f"{md.rel}:{number}: not a `key: value` line")
            continue
        current = match.group(1)
        value = match.group(2) or ""
        if value in (">", "|", ">-", "|-"):
            folded = []
            while index < md.body_start - 1 and (not lines[index].strip() or lines[index][0] in " \t"):
                folded.append(lines[index].strip())
                index += 1
            keys[current] = (number, " ".join(f for f in folded if f))
            continue
        keys[current] = (number, check_value(md, number, value, report))
    return keys


def check_value(md, number, value, report):
    if value[:1] in ('"', "'"):
        quote = value[0]
        if len(value) < 2 or not value.endswith(quote):
            report.fail("C1", f"{md.rel}:{number}: a quoted value without its closing {quote}")
            return value
        inner = value[1:-1]
        return inner.replace('\\"', '"') if quote == '"' else inner.replace("''", "'")
    if ": " in value:
        report.fail("C1", f"{md.rel}:{number}: an unquoted value holds \": \"; quote it")
    return value


# ── source normalization (C11) ──────────────────────────────────────

def normalize_source(source):
    """Joins concatenated string literals, turns interpolations into \\0, collapses whitespace."""
    source = re.sub(r'"\s*\+\s*"', "", source)
    out, i, n = [], 0, len(source)
    while i < n:
        if source.startswith("\\(", i) or source.startswith("${", i):
            # An interpolation closes on its own line; a `\(` with no close there is an escaped
            # parenthesis (a regular expression), kept as text.
            opener, closer = ("(", ")") if source[i + 1] == "(" else ("{", "}")
            depth, j = 1, i + 2
            while j < n and depth and source[j] != "\n":
                if source[j] == opener:
                    depth += 1
                elif source[j] == closer:
                    depth -= 1
                j += 1
            if depth == 0:
                out.append("\0")
                i = j
                continue
            out.append(source[i:i + 2])
            i += 2
            continue
        if source[i] == "$" and i + 1 < n and (source[i + 1].isalpha() or source[i + 1] == "_"):
            j = i + 1
            while j < n and (source[j].isalnum() or source[j] == "_"):
                j += 1
            out.append("\0")
            i = j
            continue
        out.append(source[i])
        i += 1
    text = "".join(out).replace('\\"', '"').replace("\\u{2014}", "—").replace("\\u2014", "—")
    return re.sub(r"[ \t]+", " ", text)


def diagnostic_fragments(span):
    """The literal pieces of a quoted diagnostic. Placeholders (<…>, …) and platform tags
    ([swift], [kotlin], [both]) are holes; " — " and ": " are split points too, because the CLI
    joins a verdict and its detail there ("duet record: REFUSED — " + the reason). Each piece must
    appear verbatim in a source."""
    text = re.sub(r"^✗\s*", "", span)
    parts = re.split(r"<[^<>]+>|…|\.\.\.|\[(?:swift|kotlin|both)\]| — |: ", text)
    out = []
    for part in parts:
        part = re.sub(r"\s+", " ", part).strip(" []()'\"")
        if len(re.sub(r"\W", "", part)) >= 3:
            out.append(part)
    return out


# ── the checks ──────────────────────────────────────────────────────

class Report:
    ORDER = [f"C{i}" for i in range(1, 15)]
    TITLES = {
        "C1": "frontmatter parses", "C2": "name matches the directory",
        "C3": "standard frontmatter keys", "C4": "description length",
        "C5": "line budgets", "C6": "relative links stay inside the skill",
        "C7": "Duet products, artifacts and types exist", "C8": "framework symbols are declared",
        "C9": "no version literals", "C10": "duet verbs and MCP tools exist",
        "C11": "quoted diagnostics exist", "C12": "duet-services names exist",
        "C13": "fenced commands are allowed", "C14": "manifests, eval cases and scripts",
    }

    def __init__(self):
        self.failures = {c: [] for c in self.ORDER}
        self.notes = {c: [] for c in self.ORDER}
        self.skipped = {}

    def fail(self, check, message):
        self.failures[check].append(message)

    def note(self, check, message):
        self.notes[check].append(message)

    def skip(self, check, why):
        self.skipped[check] = why

    def failed(self, check):
        return bool(self.failures[check])

    def print(self, out=sys.stdout):
        passed = failed = skipped = 0
        for check in self.ORDER:
            title = self.TITLES[check]
            if self.failures[check]:
                failed += 1
                print(f"FAIL  {check} {title}", file=out)
                for message in self.failures[check]:
                    print(f"      {message}", file=out)
            elif check in self.skipped:
                skipped += 1
                print(f"skip  {check} {title} ({self.skipped[check]})", file=out)
            else:
                passed += 1
                print(f"ok    {check} {title}", file=out)
            for message in self.notes[check]:
                print(f"      note: {message}", file=out)
        print(f"check-skill: {passed} passed, {failed} failed, {skipped} skipped", file=out)
        return failed == 0


def check_tree(root, duet_dir, tools, services, report):
    skill = os.path.join(root, "skills", "duet")
    skill_md = os.path.join(skill, "SKILL.md")
    if not os.path.isfile(skill_md):
        report.fail("C1", "skills/duet/SKILL.md does not exist")
        return
    references = sorted(os.path.join(skill, "references", f)
                        for f in os.listdir(os.path.join(skill, "references"))
                        if f.endswith(".md")) if os.path.isdir(os.path.join(skill, "references")) else []
    docs = [Markdown(p, os.path.relpath(p, root)) for p in [skill_md] + references]
    main_doc = docs[0]

    # C1–C4
    keys = frontmatter(main_doc, report)
    name = keys.get("name", (0, ""))[1]
    if name != os.path.basename(skill):
        report.fail("C2", f"name is '{name}', the directory is '{os.path.basename(skill)}'")
    extra = sorted(set(keys) - STANDARD_KEYS)
    if extra:
        report.fail("C3", f"keys outside the standard six: {', '.join(extra)}")
    description = keys.get("description", (0, ""))[1]
    if not 1 <= len(description) <= DESCRIPTION_BUDGET:
        report.fail("C4", f"description is {len(description)} characters (1–{DESCRIPTION_BUDGET})")

    # C5
    for doc in docs:
        count = len(doc.text.splitlines())
        if count > LINE_BUDGET:
            report.fail("C5", f"{doc.rel} is {count} lines (at most {LINE_BUDGET})")

    # C6
    skill_real = os.path.realpath(skill)
    for doc in docs:
        for number, line, lang in doc.walk():
            if lang is not None:
                continue
            for match in LINK.finditer(SPAN.sub("", line)):
                target = match.group(1)
                if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
                    continue
                path = target.split("#", 1)[0]
                resolved = os.path.realpath(os.path.join(os.path.dirname(doc.path), path))
                if path.startswith("/") or not (resolved + os.sep).startswith(skill_real + os.sep):
                    report.fail("C6", f"{doc.rel}:{number}: {target} leaves skills/duet/; link it by URL")
                elif not os.path.exists(resolved):
                    report.fail("C6", f"{doc.rel}:{number}: {target} does not exist")

    code = [(doc.rel, number, text) for doc in docs for number, text in doc.code()]
    spans = [(doc.rel, number, text) for doc in docs for number, text in doc.spans()]

    # C7, C8, C12: names
    duet_products = set(re.findall(r'\.library\(\s*name:\s*"([^"]+)"', read_if(os.path.join(duet_dir, "Package.swift"))))
    duet_artifacts = set(re.findall(r'include\(\s*":([a-z0-9-]+)"', read_if(os.path.join(duet_dir, "kotlin", "settings.gradle.kts"))))
    duet_source = source_corpus(duet_dir, ["swift/Sources", "kotlin"])
    services_tag = services.tags()[0] if services and services.tags() else None
    if services_tag:
        services_products = set(re.findall(r'\.library\(\s*name:\s*"([^"]+)"', services.text(services_tag, "Package.swift")))
        services_artifacts = set(re.findall(r'include\(\s*":([a-z0-9-]+)"', services.text(services_tag, "kotlin/settings.gradle.kts")))
        services_source = "\n".join(services.files(services_tag, "", (".swift", ".kt")).values())
    else:
        services_products, services_artifacts, services_source = set(), set(), ""
        report.skip("C12", "no duet-services clone" if services is None else "duet-services has no tag")

    def declared(symbol, corpus):
        pattern = (r"\b(?:class|struct|enum|protocol|actor|typealias|interface|object|func|fun|macro)"
                   r"\s+(?:<[^>\n]*>\s*)?(?:[A-Za-z_][\w.]*\.)?" + re.escape(symbol) + r"\b")
        return re.search(pattern, corpus) is not None

    seen = set()
    for rel, number, text in code:
        for coordinate in re.findall(r"\bdev\.modaal\.duet(\.services)?:([a-z][a-z0-9-]*)", text):
            key = ("artifact",) + coordinate
            if key in seen:
                continue
            seen.add(key)
            group, artifact = coordinate
            if group:
                if services_tag and artifact not in services_artifacts:
                    report.fail("C12", f"{rel}:{number}: dev.modaal.duet.services:{artifact} is not a module of duet-services {services_tag}")
            elif artifact not in duet_artifacts:
                report.fail("C7", f"{rel}:{number}: dev.modaal.duet:{artifact} is not a module in kotlin/settings.gradle.kts")
    for rel, number, text in spans:
        if text.startswith("//"):
            continue
        for product in set(re.findall(r"\bDuet[A-Z][A-Za-z0-9]*\b", text)) | ({"Duet"} if text == "Duet" else set()):
            if product in seen:
                continue
            seen.add(product)
            if product in duet_products or product in services_products:
                continue
            if declared(product, duet_source) or (services_tag and declared(product, services_source)):
                continue
            if services_tag:
                report.fail("C7", f"{rel}:{number}: {product} is no product or type of duet or duet-services {services_tag}")
            else:
                report.note("C7", f"{rel}:{number}: {product} is not in this repository; duet-services was not read")
        for identifier in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", text):
            if identifier in SYMBOLS and ("symbol", identifier) not in seen:
                seen.add(("symbol", identifier))
                if not declared(identifier, duet_source):
                    report.fail("C8", f"{rel}:{number}: {identifier} is not declared in swift/Sources or kotlin/*/src")
            if identifier in SERVICES_SYMBOLS and services_tag and ("service", identifier) not in seen:
                seen.add(("service", identifier))
                if not declared(identifier, services_source):
                    report.fail("C12", f"{rel}:{number}: {identifier} is not declared in duet-services {services_tag}")

    # C9
    for dirpath, _, filenames in os.walk(skill):
        for name_ in sorted(filenames):
            path = os.path.join(dirpath, name_)
            try:
                lines = read(path).split("\n")
            except UnicodeDecodeError:
                continue
            for number, line in enumerate(lines, 1):
                for literal in re.findall(r"[0-9]+\.[0-9]+\.[0-9]+", line):
                    report.fail("C9", f"{os.path.relpath(path, root)}:{number}: {literal}")

    # C10
    tools_tag = tools.tags()[0] if tools and tools.tags() else None
    if tools_tag:
        main_swift = tools.text(tools_tag, "Sources/duet/main.swift")
        dispatch = main_swift.split("switch command {", 1)[-1].split("default:", 1)[0]
        verbs = set(re.findall(r'case "([a-z][a-z-]*)"', dispatch))
        verbs |= set(re.findall(r'^ {4}duet ([a-z][a-z-]*)', main_swift, re.M))
        verbs |= set(re.findall(r'command == "([a-z][a-z-]*)"', main_swift))
        verbs |= {v for v in ("help", "version") if f'"{v}"' in main_swift}
        mcp_tools = set(re.findall(r'"(duet_[a-z_]+)"', tools.text(tools_tag, "Sources/duet/Mcp.swift")))
        mentioned = []
        for rel, number, text in code:
            for verb in re.findall(r"(?:^|[\s\"'(=;&|`]|\./)(?:tools/)?duet[ \t]+([a-z][a-z-]*)", text):
                mentioned.append((rel, number, verb))
            for verb in re.findall(r"duet-cli\.sh\"?[ \t]+(?:--ref[ \t=]\S+[ \t]+)?([a-z][a-z-]*)", text):
                mentioned.append((rel, number, verb))
        for doc in docs:
            for header, rows in doc.tables():
                if header and header[0] == "Verb":
                    for number, cells in rows:
                        first = SPAN.search(cells[0])
                        if first:
                            mentioned.append((doc.rel, number, first.group(2).split()[0]))
        for rel, number, verb in mentioned:
            if verb not in verbs:
                report.fail("C10", f"{rel}:{number}: duet {verb} is not a verb of duet-tools {tools_tag}")
        for rel, number, text in code + spans:
            for tool in re.findall(r"\bduet_[a-z_]+\b", text):
                if tool not in mcp_tools:
                    report.fail("C10", f"{rel}:{number}: {tool} is not an MCP tool of duet-tools {tools_tag}")
    else:
        report.skip("C10", "no duet-tools clone" if tools is None else "duet-tools has no tag")

    # C11
    quoted = []
    for doc in docs:
        for header, rows in doc.tables():
            if header and header[0].lower() in DIAGNOSTIC_HEADERS:
                for number, cells in rows:
                    for match in SPAN.finditer(cells[0]):
                        quoted.append((doc.rel, number, match.group(2).replace("\\|", "|")))
        if os.path.basename(doc.path) == "troubleshooting.md":
            for number, line, lang in doc.walk():
                if lang is None and re.match(r"^#{2,4}\s", line):
                    for match in SPAN.finditer(line):
                        quoted.append((doc.rel, number, match.group(2)))
    if tools_tag:
        local = normalize_source(duet_source)
        corpora = {}

        def corpus_at(tag):
            if tag not in corpora:
                corpora[tag] = normalize_source("\n".join(tools.files(tag, "Sources", (".swift",)).values()))
            return corpora[tag]

        newest = corpus_at(tools_tag)
        for rel, number, span in quoted:
            missing = [f for f in diagnostic_fragments(span) if f not in newest and f not in local]
            if not missing:
                continue
            found_at = None
            for tag in tools.tags()[1:]:
                corpus = corpus_at(tag)
                if all(f in corpus or f in local for f in missing):
                    found_at = tag
                    break
            if found_at:
                report.note("C11", f"{rel}:{number}: `{span}` is in duet-tools {found_at}, not {tools_tag}")
            else:
                report.fail("C11", f"{rel}:{number}: `{span}`: no duet-tools release prints {missing[0]!r}")
    else:
        report.skip("C11", "no duet-tools clone" if tools is None else "duet-tools has no tag")

    # C13
    for doc in docs:
        pending = ""
        for number, line, lang in doc.walk():
            if lang not in SHELL_LANGS:
                pending = ""
                continue
            line = pending + line
            if line.rstrip().endswith("\\"):
                pending = line.rstrip()[:-1] + " "
                continue
            pending = ""
            stripped = line.strip()
            if lang == "console":
                if not stripped.startswith("$ "):
                    continue
                stripped = stripped[2:]
            if not stripped or stripped.startswith("#"):
                continue
            for segment in shell_segments(stripped):
                if not allowed(segment):
                    report.fail("C13", f"{doc.rel}:{number}: `{segment}` starts with a command outside the allowlist")

    # C14
    check_manifests(root, skill, report)
    evals = os.path.join(root, "evals")
    if os.path.isdir(evals):
        for case in sorted(os.listdir(evals)):
            case_dir = os.path.join(evals, case)
            if not os.path.isdir(case_dir) or case == "results":
                continue
            if not os.path.isfile(os.path.join(case_dir, "prompt.md")):
                report.fail("C14", f"evals/{case}: no prompt.md")
            graders_dir = os.path.join(case_dir, "graders")
            graders = sorted(os.listdir(graders_dir)) if os.path.isdir(graders_dir) else []
            known = 0
            for grader in graders:
                match = re.search(r"^type:\s*(\S+)", read(os.path.join(graders_dir, grader)), re.M)
                if match and match.group(1) in GRADER_TYPES:
                    known += 1
                else:
                    report.fail("C14", f"evals/{case}/graders/{grader}: no type among {', '.join(sorted(GRADER_TYPES))}")
            if not known:
                report.fail("C14", f"evals/{case}: no grader")
    scripts = os.path.join(skill, "scripts")
    for name_ in sorted(os.listdir(scripts)) if os.path.isdir(scripts) else []:
        if name_.endswith(".sh"):
            result = subprocess.run(["bash", "-n", os.path.join(scripts, name_)], capture_output=True, text=True)
            if result.returncode:
                report.fail("C14", f"skills/duet/scripts/{name_}: bash -n: {result.stderr.strip()}")


def check_manifests(root, skill, report):
    """C14's manifest half: the marketplace's one entry, its plugin's manifest, and the version."""
    try:
        marketplace = json.loads(read(os.path.join(root, ".claude-plugin", "marketplace.json")))
    except (OSError, ValueError) as error:
        report.fail("C14", f".claude-plugin/marketplace.json: {error}")
        return
    entries = marketplace.get("plugins", [])
    source = entries[0].get("source") if len(entries) == 1 else None
    if not (isinstance(source, str) and source.startswith("./")):
        report.fail("C14", "marketplace.json: expected one plugin entry whose source is a ./ path")
        return
    plugin_rel = os.path.normpath(source)
    plugin_root = os.path.join(root, plugin_rel)
    manifest_rel = os.path.join(plugin_rel, ".claude-plugin", "plugin.json")
    try:
        plugin = json.loads(read(os.path.join(root, manifest_rel)))
    except (OSError, ValueError) as error:
        report.fail("C14", f"{manifest_rel}: {error}")
        return
    if plugin.get("name") != entries[0].get("name"):
        report.fail("C14", f"{manifest_rel}: name {plugin.get('name')!r} is not the marketplace entry's {entries[0].get('name')!r}")
    declared = plugin.get("skills", [])
    declared = [declared] if isinstance(declared, str) else declared
    scanned = [os.path.join(plugin_root, path) for path in declared] + [os.path.join(plugin_root, "skills")]
    target = os.path.realpath(skill)
    if not any(os.path.realpath(path) == target or os.path.realpath(os.path.join(path, "duet")) == target for path in scanned):
        report.fail("C14", f"{manifest_rel}: neither its skills paths nor {plugin_rel}/skills/ hold skills/duet/")
    icon = plugin.get("icon")
    if icon is not None and not os.path.isfile(os.path.join(plugin_root, icon)):
        report.fail("C14", f"{manifest_rel}: icon {icon!r} is not a file in the plugin")
    version = plugin.get("version")
    if not (isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+", version)):
        report.fail("C14", f"{manifest_rel}: version {version!r} is not MAJOR.MINOR.PATCH")
        return
    check_version_raised(root, plugin_rel, manifest_rel, version, report)


def check_version_raised(root, plugin_rel, manifest_rel, version, report):
    """Claude Code installs a plugin's new version string only, so a change under the plugin's root
    since the commit that set `version` fails until the version is raised."""
    def git(*args):
        return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    top = git("rev-parse", "--show-toplevel")
    if top.returncode or os.path.realpath(top.stdout.strip()) != os.path.realpath(root):
        report.note("C14", "not a git checkout: the version-raise check did not run")
        return
    if git("rev-parse", "--is-shallow-repository").stdout.strip() == "true":
        report.note("C14", "a shallow clone: the version-raise check needs the full history (fetch-depth: 0)")
        return
    base = None
    for commit in git("log", "--format=%H", "--", manifest_rel).stdout.split():
        shown = git("show", f"{commit}:{manifest_rel}")
        try:
            committed = json.loads(shown.stdout).get("version") if shown.returncode == 0 else None
        except ValueError:
            committed = None
        if committed != version:
            break
        base = commit
    if base is None:
        return  # the working tree raises the version and the raise is not committed yet
    changed = git("diff", "--name-only", base, "--", plugin_rel).stdout.splitlines()
    changed += git("ls-files", "--others", "--exclude-standard", "--", plugin_rel).stdout.splitlines()
    changed = sorted(set(changed))
    if changed:
        shown = ", ".join(changed[:3]) + (", …" if len(changed) > 3 else "")
        report.fail("C14", f"{plugin_rel}/ changed since {base[:12]}, which set version {version} ({shown}): "
                           f"raise `version` in {manifest_rel}")


def read_if(path):
    return read(path) if os.path.isfile(path) else ""


def shell_segments(line):
    """Splits a command line on &&, ||, ; and | outside quotes."""
    segments, current, quote, i = [], "", None, 0
    while i < len(line):
        char = line[i]
        if quote:
            current += char
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
            current += char
        elif line.startswith("&&", i) or line.startswith("||", i):
            segments.append(current)
            current = ""
            i += 1
        elif char in ";|":
            segments.append(current)
            current = ""
        else:
            current += char
        i += 1
    segments.append(current)
    out = []
    for segment in segments:
        segment = segment.strip().lstrip("(").rstrip(")").strip()
        segment = re.sub(r"^(?:do|then|else)\s+", "", segment)
        segment = re.sub(r"^(?:[A-Z_][A-Z0-9_]*=\S*\s+)+", "", segment)
        if segment and segment not in ("done", "fi"):
            out.append(segment)
    return out


def allowed(segment):
    if any(segment.startswith(prefix) for prefix in ALLOWED_PREFIXES):
        return True
    return segment.split()[0] in ALLOWED_COMMANDS


# ── self-test ───────────────────────────────────────────────────────

FIXTURE_SKILL = """---
name: duet
description: "A skill for the self-test."
license: MIT
metadata:
  repository: https://example.invalid/duet
---

# Self-test

See [the reference](references/model.md). `Store` lives in `DuetShells`; Kotlin uses
`dev.modaal.duet:kernel`, and services come as `DuetTelemetry` and `dev.modaal.duet.services:telemetry`.
`Themeable` is a services symbol. The MCP server serves `duet_verify`.

| Verb | What it does |
| --- | --- |
| `verify [--feature <f>]` | the lanes |

| Output | Action |
| --- | --- |
| `duet verify: FAIL in <n> lanes` | read it |
| `an older message` | read it |
| `duet lint: FAIL — the row names no scenario` | read it |

```bash
tools/duet verify
"${CLAUDE_SKILL_DIR}/scripts/duet-cli.sh" lint && git status
```
"""

FIXTURE_FILES = {
    "skills/duet/references/model.md": "# Model\n\nBack to [the skill](../SKILL.md).\n",
    "skills/duet/scripts/duet-cli.sh": "#!/bin/bash\necho ok\n",
    ".claude-plugin/marketplace.json": json.dumps({"name": "m", "plugins": [{"name": "p", "source": "./skills"}]}),
    "skills/.claude-plugin/plugin.json": json.dumps({"name": "p", "version": "1.0.0", "skills": "./duet"}),
    "evals/case/prompt.md": "---\ndescription: d\n---\nprompt\n",
    "evals/case/graders/fired.md": "---\ntype: tool_used\ntool: Skill\n---\n",
    "duet/Package.swift": '.library(name: "DuetShells", targets: ["DuetShells"]),\n',
    "duet/swift/Sources/DuetShells/Store.swift": "public final class Store {}\n",
    "duet/kotlin/settings.gradle.kts": 'include(":kernel")\n',
}

TOOLS_V1 = {
    "Sources/duet/main.swift": 'switch command {\ncase "verify":\n  break\ncase "lint":\n  break\ndefault:\n  break\n}\nprint("an older message")\n',
    "Sources/duet/Mcp.swift": 'let names = ["duet_verify"]\n',
}
TOOLS_V2 = {
    "Sources/duet/main.swift": 'switch command {\ncase "verify":\n  break\ncase "lint":\n  break\ndefault:\n  break\n}\nprint("duet verify: FAIL in \\(n) lanes")\nprint("duet lint: FAIL — \\(why)")\nlet why = "the row names no scenario"\n',
    "Sources/duet/Mcp.swift": 'let names = ["duet_verify"]\n',
}
SERVICES_V1 = {
    "Package.swift": '.library(name: "DuetTelemetry", targets: ["DuetTelemetry"]),\n',
    "kotlin/settings.gradle.kts": 'include(":telemetry")\n',
    "swift/Sources/DuetTheming/Themeable.swift": "public protocol Themeable {}\n",
}


def write_tree(base, files):
    for rel, content in files.items():
        path = os.path.join(base, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)


def scratch_git(path, *args):
    subprocess.run(["git", "-C", path, "-c", "user.name=self-test", "-c", "user.email=self-test@example.invalid",
                    "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", *args],
                   check=True, capture_output=True)


def git_repo(path, versions):
    os.makedirs(path)
    def git(*args):
        scratch_git(path, *args)
    git("init", "-q")
    for tag, files in versions:
        for name_ in os.listdir(path):
            if name_ != ".git":
                shutil.rmtree(os.path.join(path, name_))
        write_tree(path, files)
        git("add", "-A")
        git("commit", "-q", "-m", tag)
        git("tag", tag)
    return GitTree(path)


def append(path, text):
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(text)


def replace(path, old, new):
    content = read(path)
    if old not in content:
        raise SystemExit(f"self-test: the fixture lacks {old!r}")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content.replace(old, new, 1))


SEEDS = {
    "C1": lambda r: replace(f"{r}/skills/duet/SKILL.md", 'description: "A skill for the self-test."', "description: A skill: for the self-test"),
    "C2": lambda r: replace(f"{r}/skills/duet/SKILL.md", "name: duet", "name: other"),
    "C3": lambda r: replace(f"{r}/skills/duet/SKILL.md", "license: MIT", "license: MIT\nversion: one"),
    "C4": lambda r: replace(f"{r}/skills/duet/SKILL.md", '"A skill for the self-test."', '"' + "x" * 1025 + '"'),
    "C5": lambda r: append(f"{r}/skills/duet/references/model.md", "line\n" * 251),
    "C6": lambda r: append(f"{r}/skills/duet/SKILL.md", "\nSee [the README](../../README.md).\n"),
    "C7": lambda r: append(f"{r}/skills/duet/SKILL.md", "\nAdd `DuetNowhere`.\n"),
    "C8": lambda r: append(f"{r}/skills/duet/SKILL.md", "\nMount it in a `RetainedRoot`.\n"),
    "C9": lambda r: append(f"{r}/skills/duet/references/model.md", "\nPin 1.2.3.\n"),
    "C10": lambda r: append(f"{r}/skills/duet/SKILL.md", "\nRun `tools/duet frobnicate`.\n"),
    "C11": lambda r: append(f"{r}/skills/duet/SKILL.md", "\n| Output | Action |\n| --- | --- |\n| `no release prints this` | x |\n"),
    "C12": lambda r: append(f"{r}/skills/duet/SKILL.md", "\nAdd `dev.modaal.duet.services:nowhere`.\n"),
    "C13": lambda r: append(f"{r}/skills/duet/SKILL.md", "\n```bash\nnpm install something\n```\n"),
    "C14": lambda r: write_tree(r, {"skills/.claude-plugin/plugin.json": json.dumps({"name": "renamed", "version": "1.0.0", "skills": "./duet"})}),
    "C14 version": lambda r: commit_without_raise(r),
}


def commit_without_raise(root):
    """A commit that sets version 1.0.0, then a commit that changes the skill and keeps it."""
    scratch_git(root, "init", "-q")
    scratch_git(root, "add", "-A")
    scratch_git(root, "commit", "-q", "-m", "1.0.0")
    append(f"{root}/skills/duet/references/model.md", "\nA paragraph.\n")
    scratch_git(root, "commit", "-q", "-am", "the skill changes, the version stays")


def self_test():
    scratch = tempfile.mkdtemp(prefix="check-skill-self-test.")
    try:
        tools = git_repo(os.path.join(scratch, "tools"), [("1.0.0", TOOLS_V1), ("1.1.0", TOOLS_V2)])
        services = git_repo(os.path.join(scratch, "services"), [("2.0.0", SERVICES_V1)])
        ok = True

        def fresh(name_):
            root = os.path.join(scratch, name_)
            write_tree(root, dict(FIXTURE_FILES, **{"skills/duet/SKILL.md": FIXTURE_SKILL}))
            return root

        root = fresh("baseline")
        report = Report()
        check_tree(root, os.path.join(root, "duet"), tools, services, report)
        if any(report.failures.values()) or report.skipped:
            print("self-test: FAIL  the baseline fixture does not pass")
            report.print()
            ok = False
        elif not any("1.0.0" in n for n in report.notes["C11"]):
            print("self-test: FAIL  C11 did not note the message only an older tag prints")
            ok = False
        else:
            print("self-test: ok    the baseline fixture passes, C11 notes the older tag")
        for check, seed in SEEDS.items():
            root = fresh(f"seed-{check.replace(' ', '-')}")
            seed(root)
            report = Report()
            check_tree(root, os.path.join(root, "duet"), tools, services, report)
            if report.failed(check.split()[0]):
                print(f"self-test: ok    {check} fails on its seeded violation")
            else:
                print(f"self-test: FAIL  {check} passed its seeded violation")
                ok = False
        print("self-test: " + ("every check goes red on its violation" if ok else "FAIL"))
        return 0 if ok else 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


# ── entry ───────────────────────────────────────────────────────────

def main(argv):
    root, args = argv[0], argv[1:]
    offline, tools_dir, services_dir = False, None, None
    while args:
        arg = args.pop(0)
        if arg == "--self-test":
            return self_test()
        if arg == "--offline":
            offline = True
        elif arg in ("--tools-dir", "--services-dir") and args:
            value = os.path.abspath(args.pop(0))
            if arg == "--tools-dir":
                tools_dir = value
            else:
                services_dir = value
        else:
            print("usage: check-skill.sh [--offline] [--tools-dir <git checkout>] [--services-dir <git checkout>] | --self-test", file=sys.stderr)
            return 2
    scratch = tempfile.mkdtemp(prefix="check-skill.")
    try:
        tools = services = None
        if tools_dir:
            tools = GitTree(tools_dir)
        elif not offline:
            try:
                tools = clone(TOOLS_URL, os.path.join(scratch, "duet-tools"))
            except subprocess.CalledProcessError as error:
                print(f"check-skill: cloning {TOOLS_URL} failed: {error.stderr.strip()}", file=sys.stderr)
                return 2
        if services_dir:
            services = GitTree(services_dir)
        elif not offline:
            try:
                services = clone(SERVICES_URL, os.path.join(scratch, "duet-services"))
            except subprocess.CalledProcessError as error:
                print(f"check-skill: cloning {SERVICES_URL} failed: {error.stderr.strip()}", file=sys.stderr)
                return 2
        report = Report()
        check_tree(root, root, tools, services, report)
        if tools:
            report.note("C10", f"duet-tools {tools.tags()[0] if tools.tags() else '(no tag)'}")
        if services:
            report.note("C12", f"duet-services {services.tags()[0] if services.tags() else '(no tag)'}")
        return 0 if report.print() else 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


sys.exit(main(sys.argv[1:]))
PY
