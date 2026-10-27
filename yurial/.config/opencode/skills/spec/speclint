#!/usr/bin/env python3
"""Mechanical Markdown specification, index, and glossary linter.

The rules implemented here are the executable interpretation of SPECLINT.md.
Semantic quality and correctness of requirement meaning are intentionally out of scope.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

CLEAN = 0
WARNING = 1
ERROR = 2
FAMILIES = {"R": "Requirements", "I": "Implementation", "E": "Examples", "V": "Verification", "T": "Tests", "J": "Justification"}
RECORD_SECTIONS = {"Requirements", "Examples", "Implementation", "Verification", "Tests", "Justification"}
ALLOWED_VERIFICATION = {"automated", "scenario", "manual", "analysis"}
PREFIX_RE = re.compile(r"^- ([REIVTJ]\d+(?:\.\d+)*)\.(?:\s|$)")
NUMERIC_RE = re.compile(r"(?<![A-Za-z0-9_.])\d+(?:[.,]\d+)*(?:[A-Za-z][A-Za-z0-9_-]*)?(?![A-Za-z0-9_])")
INLINE_CODE_RE = re.compile(r"(`+).*?\1")

@dataclass
class Finding:
    path: Path
    line: int
    message: str
    warning: bool = False

@dataclass
class Entry:
    family: str
    number: str
    line: int
    section: str
    text: str
    indent: int
    @property
    def id(self) -> str:
        return f"{self.family}{self.number}"
def section_name(heading: str) -> str:
    # The first alphabetic word is the section key; case is significant only by canonicalization.
    m = re.search(r"[A-Za-z]+", heading)
    if not m:
        return ""
    word = m.group(0)
    known = {s.lower(): s for s in (set(RECORD_SECTIONS) | {"Overview", "Scope", "Definitions", "Interface", "Configuration", "Dependencies", "Used by", "Usage constraints", "Error handling"})}
    return known.get(word.lower(), word)


def read_markdown(path: Path) -> tuple[list[str], list[bool]]:
    text = path.read_text(encoding="utf-8-sig")
    lines = text.splitlines()
    in_fence = False
    fenced: list[bool] = []
    for line in lines:
        # Fence starts only in column zero. Closing marker may use a different character/length.
        stripped = line
        match = re.match(r"^(`{3,}|~{3,})(.*)$", stripped)
        if not in_fence and match:
            in_fence = True
            fenced.append(True)
            continue
        if in_fence:
            fenced.append(True)
            close = re.match(r"^(`{3,}|~{3,})\s*$", stripped)
            if close:
                in_fence = False
            continue
        fenced.append(False)
    return lines, fenced


def scan_spec(path: Path) -> list[Finding]:
    findings: list[Finding] = []
    try:
        lines, fenced = read_markdown(path)
    except (OSError, UnicodeError) as exc:
        return [Finding(path, 1, f"cannot read Markdown file: {exc}")]

    sections: list[str] = [""] * len(lines)
    current = ""
    for i, line in enumerate(lines):
        if not fenced[i]:
            hm = re.match(r"^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
            if hm:
                current = section_name(hm.group(1))
        sections[i] = current

    entries: list[Entry] = []
    seen: dict[str, int] = {}
    for i, line in enumerate(lines):
        if fenced[i]:
            continue
        sec = sections[i]
        # Section headings are structural, not section-content records.
        if not fenced[i] and re.match(r"^ {0,3}#{1,6}\s+", line):
            continue
        # Number scanner excludes inline code and specified sections.
        if sec not in {"Configuration", "Examples"}:
            cleaned = INLINE_CODE_RE.sub(lambda m: " " * len(m.group(0)), line)
            for m in NUMERIC_RE.finditer(cleaned):
                token = m.group(0)
                # A numeric dotted version (for example 1.2.3) is an identifier,
                # not a decimal literal. Two-component decimals remain reportable.
                if token.count(".") >= 2 and "," not in token and re.fullmatch(r"\d+(?:\.\d+){2,}", token):
                    continue
                col = m.start() + 1
                findings.append(Finding(path, i + 1, f"bare numeric literal {token!r} outside Configuration/Examples at column {col}"))

        stripped = line.lstrip(" \t")
        indent = len(line) - len(stripped)
        pm = PREFIX_RE.match(stripped)
        if pm:
            ident = pm.group(1)
            family = ident[0]
            number = ident[1:]
            if sec not in RECORD_SECTIONS:
                findings.append(Finding(path, i + 1, f"prefixed entry {ident} is outside its record section"))
            elif FAMILIES[family] != sec:
                findings.append(Finding(path, i + 1, f"{ident} must be in section {FAMILIES[family]}, not {sec}"))
            if indent:
                findings.append(Finding(path, i + 1, f"prefixed entry {ident} starts with indentation"))
            if ident in seen:
                findings.append(Finding(path, i + 1, f"duplicate ID {ident}; first defined on line {seen[ident]}"))
            else:
                seen[ident] = i + 1
            entries.append(Entry(family, number, i + 1, sec, line[pm.end():].strip(), indent))
        elif sec in RECORD_SECTIONS and line.strip():
            # Every nonempty line in these sections must be a top-level prefixed record.
            findings.append(Finding(path, i + 1, f"nonempty line in {sec} must start at column 0 with '- ' and the section's ID prefix"))
        if indent and re.match(r"^\s+-\s+[REIVTJ]\d", line):
            findings.append(Finding(path, i + 1, "prefixed entry is indented; Markdown nesting cannot express record hierarchy"))
        if i > 0 and indent and sections[i] in RECORD_SECTIONS and not fenced[i] and lines[i-1].strip():
            if PREFIX_RE.match(lines[i-1].lstrip()) and len(lines[i-1]) - len(lines[i-1].lstrip()) == 0:
                findings.append(Finding(path, i + 1, "indented continuation after a prefixed entry is not allowed"))

    ids = {e.id: e for e in entries}
    by_family: dict[str, list[Entry]] = {}
    for e in entries:
        by_family.setdefault(e.family, []).append(e)
        parts = e.number.split(".")
        for n in range(1, len(parts)):
            parent = e.family + ".".join(parts[:n])
            if parent not in ids:
                findings.append(Finding(path, e.line, f"{e.id} has missing parent {parent}"))
    for family, family_entries in by_family.items():
        nums = {e.number for e in family_entries}
        for e in family_entries:
            child_prefix = e.number + "."
            has_child = any(n.startswith(child_prefix) for n in nums)
            # A parent with children must end in colon; a leaf must not be a group label.
            if has_child and not e.text.endswith(":"):
                findings.append(Finding(path, e.line, f"group entry {e.id} must end with ':'"))
            if not has_child and e.text.endswith(":"):
                findings.append(Finding(path, e.line, f"leaf entry {e.id} must not end with ':'"))

    # Requirement markers and Tests coverage.
    r_entries = {e.id: e for e in entries if e.family == "R"}
    e_entries = {e.id: e for e in entries if e.family == "E"}
    t_entries = [e for e in entries if e.family == "T"]
    leaf_r = [e for e in r_entries.values() if not any(x.number.startswith(e.number + ".") for x in r_entries.values())]
    leaf_t = [e for e in t_entries if not any(x.number.startswith(e.number + ".") for x in t_entries)]
    for e in e_entries.values():
        rid = "R" + e.number
        if rid not in r_entries:
            findings.append(Finding(path, e.line, f"{e.id} must mirror an existing {rid}"))
    for r in leaf_r:
        vals = re.findall(r"(?:^|\s)verification=([A-Za-z_-]+)", r.text)
        if len(vals) != 1 or vals[0] not in ALLOWED_VERIFICATION:
            findings.append(Finding(path, r.line, f"leaf {r.id} must contain exactly one verification marker with value one of {', '.join(sorted(ALLOWED_VERIFICATION))}"))
    t_refs: dict[str, list[Entry]] = {}
    for t in leaf_t:
        refs_match = re.search(r"(?:^|\s)R-ID=([^;]+)", t.text)
        if not refs_match:
            findings.append(Finding(path, t.line, f"leaf {t.id} must identify checked requirements with R-ID=..."))
            continue
        refs = [x.strip() for x in refs_match.group(1).split(",") if x.strip()]
        for rid in refs:
            if rid not in r_entries:
                findings.append(Finding(path, t.line, f"{t.id} references nonexistent {rid}"))
            elif any(x.number.startswith(r_entries[rid].number + ".") for x in r_entries.values()):
                findings.append(Finding(path, t.line, f"{t.id} may reference only leaf R-ID; {rid} is a group"))
            else:
                markers = re.findall(r"(?:^|\s)verification=([A-Za-z_-]+)", r_entries[rid].text)
                if len(markers) != 1 or markers[0] not in {"automated", "scenario"}:
                    findings.append(Finding(path, t.line, f"{t.id} may reference only R-ID with verification=automated or verification=scenario; {rid} does not qualify"))
                else:
                    t_refs.setdefault(rid, []).append(t)
        for field in ("conditions=", "expected="):
            if field not in t.text:
                findings.append(Finding(path, t.line, f"leaf {t.id} must contain {field[:-1]} field"))
    for r in leaf_r:
        vals = re.findall(r"(?:^|\s)verification=([A-Za-z_-]+)", r.text)
        if vals and vals[0] in {"automated", "scenario"} and r.id not in t_refs:
            findings.append(Finding(path, r.line, f"{r.id} with verification={vals[0]} must be referenced by at least one leaf T-ID"))
    return findings


def parse_fields(text: str) -> dict[str, str]:
    """Parse index/glossary fields in plain, bold, or backtick Markdown forms."""
    field_re = re.compile(
        r"(?<![A-Za-z])(?P<key>Defined in|Path|Reference|Status|Summary)"
        r"(?:\*\*|`)?\s*:\s*(?:\*\*|`)?",
        re.I,
    )
    matches = list(field_re.finditer(text))
    result: dict[str, str] = {}
    for index, match in enumerate(matches):
        key = match.group("key").lower()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        value = text[match.end():end].strip()
        value = re.sub(r"(?:\*\*|`)+$", "", value).strip()
        value = value.rstrip(".;")
        if value:
            result[key] = value
    return result


def repo_root(path: Path) -> Path | None:
    try:
        p = path.resolve()
        for parent in (p.parent, *p.parents):
            if (parent / ".git").exists():
                return parent
        cp = subprocess.run(["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=2)
        if cp.returncode == 0 and cp.stdout.strip():
            return Path(cp.stdout.strip()).resolve()
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def table_cells(line: str) -> list[str] | None:
    """Return trimmed Markdown table cells, or None for a non-table line."""
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return None
    return [cell.strip().strip(" `*_ ") for cell in stripped[1:-1].split("|")]


def is_table_separator(cells: list[str]) -> bool:
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells)


def scan_index(path: Path) -> list[Finding]:
    findings: list[Finding] = []
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as exc:
        return [Finding(path, 1, f"cannot read index: {exc}")]
    root = repo_root(path)
    specs_dir = next((p for p in (path.parent, *path.parents) if p.name == "specs"), None)
    base = root or (specs_dir.parent if specs_dir else path.parent)
    header = ["Path", "Reference", "Status", "Summary"]
    header_line = None
    rows: list[tuple[int, list[str]]] = []
    for i, line in enumerate(lines, 1):
        cells = table_cells(line)
        if cells is None:
            continue
        normalized = [re.sub(r"[*`]", "", c).strip() for c in cells]
        if normalized == header:
            header_line = i
            continue
        if is_table_separator(cells):
            if header_line is None:
                findings.append(Finding(path, i, "table separator appears before the required index header"))
            continue
        if header_line is not None:
            rows.append((i, cells))
    if header_line is None:
        return [Finding(path, 1, "index must contain a Markdown table with header: Path | Reference | Status | Summary")]
    for line_no, cells in rows:
        if len(cells) != 4:
            findings.append(Finding(path, line_no, "index row must contain exactly four cells"))
            continue
        fields = dict(zip(("path", "reference", "status", "summary"), cells))
        for key in ("path", "reference", "status", "summary"):
            if not fields[key]:
                findings.append(Finding(path, line_no, f"index row missing required field {key.title()}"))
        status = fields["status"]
        if status and status not in {"draft", "stable"}:
            findings.append(Finding(path, line_no, f"invalid Status {status!r}; expected draft or stable"))
        ref = fields["reference"]
        if ref and not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", ref):
            findings.append(Finding(path, line_no, f"invalid Reference {ref!r}; expected lowercase ASCII letters/digits separated by single hyphens"))
        value = fields["path"]
        if value:
            target = (base / value).resolve()
            if not target.exists():
                findings.append(Finding(path, line_no, f"index Path does not exist: {value}"))
    return findings


def scan_glossary(path: Path, reference_ids: set[str] | None) -> list[Finding]:
    findings: list[Finding] = []
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as exc:
        return [Finding(path, 1, f"cannot read glossary: {exc}")]
    header = ["Term ID", "Definition", "Defined in"]
    header_line = None
    entries: list[tuple[int, str]] = []
    rows: list[tuple[int, list[str]]] = []
    for i, line in enumerate(lines, 1):
        cells = table_cells(line)
        if cells is None:
            continue
        normalized = [re.sub(r"[*`]", "", c).strip() for c in cells]
        if normalized == header:
            header_line = i
            continue
        if is_table_separator(cells):
            continue
        if header_line is not None:
            rows.append((i, cells))
    if header_line is None:
        return [Finding(path, 1, "glossary must contain a Markdown table with header: Term ID | Definition | Defined in")]
    term_pattern = r"[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)"
    for line_no, cells in rows:
        if len(cells) != 3:
            findings.append(Finding(path, line_no, "glossary row must contain exactly three cells"))
            continue
        term_id, definition, defined_in = cells
        if not term_id:
            findings.append(Finding(path, line_no, "glossary row missing required field Term ID"))
            continue
        if not re.fullmatch(term_pattern, term_id) or not term_id.isascii():
            findings.append(Finding(path, line_no, f"invalid glossary term ID {term_id!r}; expected <reference>/<term> using lowercase ASCII letters, digits, and hyphens"))
        if not definition:
            findings.append(Finding(path, line_no, "glossary row missing required field Definition"))
        defined_match = re.match(r"^([a-z0-9]+(?:-[a-z0-9]+)*)", defined_in)
        if not defined_in:
            findings.append(Finding(path, line_no, "glossary row missing required field Defined in"))
        elif not defined_match:
            findings.append(Finding(path, line_no, f"invalid Defined in value {defined_in!r}"))
        else:
            defined_ref = defined_match.group(1)
            if "/" in term_id and defined_ref != term_id.split("/", 1)[0]:
                findings.append(Finding(path, line_no, f"Defined in {defined_ref!r} must equal term ID prefix {term_id.split('/', 1)[0]!r}"))
            elif reference_ids is not None and defined_ref not in reference_ids:
                findings.append(Finding(path, line_no, f"Defined in prefix {defined_ref!r} does not resolve to an index Reference ID"))
        entries.append((line_no, term_id))
    ids = [term for _, term in entries]
    if ids != sorted(ids):
        if entries:
            findings.append(Finding(path, entries[0][0], "glossary term IDs are not sorted alphabetically"))
    return findings


def discover(paths: Iterable[Path]) -> tuple[list[Path], list[Finding]]:
    files: set[Path] = set()
    errors: list[Finding] = []
    for path in paths:
        if not path.exists():
            errors.append(Finding(path, 1, "path does not exist"))
            continue
        if path.is_file():
            if path.suffix != ".md":
                errors.append(Finding(path, 1, "file path must have .md extension"))
            else:
                files.add(path.resolve())
        elif path.is_dir():
            try:
                files.update(p.resolve() for p in path.rglob("*") if p.is_file() and p.suffix == ".md")
            except OSError as exc:
                errors.append(Finding(path, 1, f"cannot traverse directory: {exc}"))
        else:
            errors.append(Finding(path, 1, "path must be a Markdown file or directory"))
    ordered = sorted(files, key=lambda p: (0 if p.name == "index.md" else 1 if p.name == "GLOSSARY.md" else 2, str(p)))
    return ordered, errors


def collect_reference_ids(files: list[Path]) -> tuple[set[str] | None, list[Finding]]:
    refs: set[str] = set()
    indexes = [p for p in files if p.name == "index.md"]
    if not indexes:
        return None, []
    for path in indexes:
        try:
            lines = path.read_text(encoding="utf-8-sig").splitlines()
        except (OSError, UnicodeError):
            continue
        header_seen = False
        for line in lines:
            cells = table_cells(line)
            if cells is None:
                continue
            normalized = [re.sub(r"[*`]", "", c).strip() for c in cells]
            if normalized == ["Path", "Reference", "Status", "Summary"]:
                header_seen = True
                continue
            if not header_seen or is_table_separator(cells) or len(cells) != 4:
                continue
            ref = cells[1]
            if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", ref):
                refs.add(ref)
    return (refs if refs else None), []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="speclint.py", description="Mechanically lint Markdown specifications, indexes, and glossaries.")
    parser.add_argument("path", nargs="*", help="Markdown file or directory (recursive)")
    args = parser.parse_args(argv)
    if not args.path:
        print("speclint: error: at least one path is required", file=sys.stderr)
        return ERROR
    files, findings = discover(Path(p) for p in args.path)
    if not files and not findings:
        findings.append(Finding(Path(args.path[0]), 1, "no Markdown files found"))
    refs, _ = collect_reference_ids(files)
    for path in files:
        if path.name == "index.md":
            findings.extend(scan_index(path))
        elif path.name == "GLOSSARY.md":
            if refs is None:
                findings.append(Finding(path, 1, "Reference IDs could not be collected; glossary prefix-resolution check skipped", True))
            findings.extend(scan_glossary(path, refs))
        else:
            findings.extend(scan_spec(path))
    errors = [f for f in findings if not f.warning]
    warnings = [f for f in findings if f.warning]
    for f in sorted(findings, key=lambda x: (str(x.path), x.line, x.warning, x.message)):
        if f.warning:
            print(f"speclint: warning: {f.path}:{f.line}: {f.message}", file=sys.stderr)
        else:
            print(f"{f.path}:{f.line}: {f.message}", file=sys.stderr)
    if errors:
        return ERROR
    if warnings:
        return WARNING
    return CLEAN

if __name__ == "__main__":
    raise SystemExit(main())
