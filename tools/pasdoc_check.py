#!/usr/bin/env python3
"""PasDoc coverage and source hygiene checker for the whisper.cpp binding
(taken from TSteamAPI, folders adapted).

Run from the repository root before every delivery:

    python3 tools/pasdoc_check.py

Checks every .pas / .inc / .dpr / .dpk under lib/, fmx/, vcl/, lcl/, packages/ and demos/:

  * sources are pure ASCII (use #$xxxx codes for other characters);
  * no '{' inside a { } comment (Pascal comments do not nest, so an example
    such as {$I Whisper.inc} inside a doc comment would end it early);
  * each unit has a PasDoc comment before the "unit" keyword;
  * in the interface section every type, constant, variable, routine,
    field (private ones included), method and property is documented,
    either by a comment ending on the line(s) above it or by a trailing
    "{< ... }" / "//< ..." comment on the same line;
  * no plain trailing "// ..." comments in the interface section (PasDoc
    attaches them to the following item).

Enumeration values, record variant parts and parameter lists are not checked.
Files in VENDORED are not checked at all: unchanged copies of the owner's
units from other projects, kept byte-for-byte so they can be compared with
their source (owner's decision 2026-11-01).
Exit code 0 = clean, 1 = problems found (listed as file:line: message).
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ["lib", "fmx", "vcl", "lcl", "packages", "demos"]
SOURCE_EXT = (".pas", ".inc", ".dpr", ".dpk")
# Unchanged copies of the owner's units from his other repositories - not
# checked (they keep their own style: UTF-8 BOM, //** comments, private
# members without PasDoc). Path from the repository root -> where it comes from.
VENDORED = {}
# Third-party units the owner copies in LOCALLY (git-ignored, never in the
# repository) - not ours to check.
LOCAL_ONLY = {}

DECL_KEYWORDS = re.compile(
    r"^(class\s+)?(function|procedure|constructor|destructor|property|operator)\b", re.I)
SECTION_KEYWORDS = re.compile(r"^(type|const|var|threadvar|resourcestring)\b", re.I)
VISIBILITY = re.compile(r"^(strict\s+)?(private|protected|public|published)\b(\s+(type|const|var))?\s*$", re.I)
NAMED_DECL = re.compile(r"^(class\s+var\s+)?[A-Za-z_][A-Za-z0-9_]*(<[^>]*>)?\s*(,\s*[A-Za-z_][A-Za-z0-9_]*\s*)*[:=]")
ATTRIBUTE = re.compile(r"^\[.*\]\s*$")


def strip_strings(line):
    return re.sub(r"'[^']*'", "''", line)


class Checker:
    def __init__(self):
        self.problems = []

    def report(self, path, lineno, msg):
        rel = os.path.relpath(path, ROOT)
        self.problems.append(f"{rel}:{lineno}: {msg}")

    # ------------------------------------------------------------------ ascii
    def check_ascii(self, path, data):
        for i, line in enumerate(data.split(b"\n"), 1):
            for ch in line:
                if ch > 127:
                    self.report(path, i, "non-ASCII character (use #$xxxx)")
                    break

    # ------------------------------------------------------------- nesting
    def check_nesting(self, path, text):
        """Pascal comments do not nest: a '{' inside a { } comment (for example
        an example {$I ...} directive) ends the comment at its '}'."""
        i, n, line = 0, len(text), 1
        while i < n:
            c = text[i]
            if c == "\n":
                line += 1
                i += 1
            elif c == "'":
                j = text.find("'", i + 1)
                while j != -1 and j + 1 < n and text[j + 1] == "'":
                    j = text.find("'", j + 2)
                i = n if j == -1 else j + 1
            elif text.startswith("//", i):
                j = text.find("\n", i)
                i = n if j == -1 else j
            elif text.startswith("(*", i):
                j = text.find("*)", i + 2)
                j = n if j == -1 else j
                line += text.count("\n", i, j)
                i = j + 2
            elif c == "{":
                start_line = line
                j = text.find("}", i + 1)
                j = n if j == -1 else j
                body = text[i + 1:j]
                if not body.startswith("$") and "{" in body:
                    self.report(path, start_line, "'{' inside a { } comment - comments do not nest; use (* *)")
                line += text.count("\n", i, j)
                i = j + 1
            else:
                i += 1

    # ---------------------------------------------------------------- pasdoc
    def check_pasdoc(self, path, text):
        lines = text.split("\n")
        n = len(lines)
        # unit header comment
        unit_idx = None
        for i, l in enumerate(lines):
            if re.match(r"^\s*(unit|program|package|library)\s+[A-Za-z0-9_.]+\s*;", l, re.I):
                unit_idx = i
                break
        if unit_idx is None:
            return
        if re.match(r"^\s*unit\s", lines[unit_idx], re.I):
            j = unit_idx - 1
            while j >= 0 and lines[j].strip() == "":
                j -= 1
            if j < 0 or not (lines[j].rstrip().endswith("}") or lines[j].rstrip().endswith("*)")):
                self.report(path, unit_idx + 1, "unit has no PasDoc header comment")
        else:
            return  # programs / packages: header only is recommended, not enforced

        # interface section only
        start = end = None
        for i in range(unit_idx, n):
            if re.match(r"^\s*interface\s*$", lines[i], re.I) and start is None:
                start = i
            if re.match(r"^\s*implementation\s*$", lines[i], re.I):
                end = i
                break
        if start is None or end is None:
            return

        in_comment = None      # '{' or '(*'
        last_comment_end = -10  # line index where the last comment ended
        paren_depth = 0        # inside enum / parameter lists
        in_record_case = False
        in_uses = False
        for i in range(start + 1, end):
            raw = lines[i]
            line = strip_strings(raw).strip()

            # track multi-line comments
            if in_comment:
                close = "}" if in_comment == "{" else "*)"
                if close in line:
                    in_comment = None
                    last_comment_end = i
                    rest = line.split(close, 1)[1].strip()
                    if not rest:
                        continue
                    line = rest
                else:
                    continue
            if line.startswith("{$"):
                continue
            if line.startswith("//"):
                # "// ---" section dividers are layout, not documentation
                if not re.match(r"^//\s*-{3,}", line):
                    last_comment_end = i
                continue
            if line.startswith("{") or line.startswith("(*"):
                opener = "{" if line.startswith("{") else "(*"
                close = "}" if opener == "{" else "*)"
                if close in line:
                    rest = line.split(close, 1)[1].strip()
                    last_comment_end = i
                    if not rest:
                        continue
                    line = rest
                else:
                    in_comment = opener
                    continue
            if line == "":
                continue

            if in_uses:
                if ";" in line:
                    in_uses = False
                continue
            if re.match(r"^uses\b", line, re.I):
                in_uses = ";" not in line
                continue

            if re.search(r"\S\s*//(?!<)", line):
                self.report(path, i + 1, "trailing // comment would document the NEXT item; use //< or a comment above")

            documented = (last_comment_end == i - 1 or "{<" in line or "//<" in line)

            if paren_depth > 0:
                paren_depth += line.count("(") - line.count(")")
                continue

            if SECTION_KEYWORDS.match(line) or VISIBILITY.match(line) or ATTRIBUTE.match(line):
                # attributes / visibility do not break a preceding comment
                if ATTRIBUTE.match(line) and last_comment_end == i - 1:
                    last_comment_end = i
                continue
            if re.match(r"^(end|private|public|protected|published)\b", line, re.I):
                in_record_case = False
                continue
            if re.match(r"^case\b", line, re.I):
                in_record_case = True
                continue
            if in_record_case:
                continue

            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*\s*=\s*(class|interface)\s*;", line, re.I):
                continue  # forward declaration
            is_decl = bool(DECL_KEYWORDS.match(line) or NAMED_DECL.match(line))
            if is_decl and not documented:
                name = re.split(r"[\s:=(;<]", re.sub(DECL_KEYWORDS, "", line).strip() or line)[0]
                self.report(path, i + 1, f"undocumented declaration: {name or line[:40]}")

            # skip bodies of enumerations / multi-line parameter lists
            paren_depth += line.count("(") - line.count(")")

    def run(self):
        for d in SCAN_DIRS:
            base = os.path.join(ROOT, d)
            for dirpath, _, files in os.walk(base):
                if any(part in ("__history", "__recovery") for part in dirpath.split(os.sep)):
                    continue
                for f in sorted(files):
                    if not f.lower().endswith(SOURCE_EXT):
                        continue
                    path = os.path.join(dirpath, f)
                    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                    if rel in VENDORED or rel in LOCAL_ONLY:
                        continue
                    with open(path, "rb") as fh:
                        data = fh.read()
                    self.check_ascii(path, data)
                    self.check_nesting(path, data.decode("latin-1"))
                    if f.lower().endswith(".pas"):
                        self.check_pasdoc(path, data.decode("latin-1"))
        return self.problems


def main():
    problems = Checker().run()
    for p in problems:
        print(p)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
