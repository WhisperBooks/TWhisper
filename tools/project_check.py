#!/usr/bin/env python3
"""Checks project files before delivery.

    python3 tools/project_check.py

For every .dproj / .groupproj under the repository:
  * UTF-8 BOM present and the XML parses;
  * every DCCReference to a .pas exists on disk;
  * the .pas units of the .dproj match the "in '...'" units of the
    .dpr / .dpk (same set, compared case-insensitively);
  * every project in a .groupproj exists;
  * BUILD ORDER of WhisperAPI.groupproj (owner's rule, 2026-11-14): every
    package after the packages it requires (WhisperAPI, then WhisperAPIFMX,
    then the design package dclWhisperAPIFMX), every application after all
    packages, and the Build / Clean / Make targets in the same order as the
    Projects list - another order breaks Build All and Delphi's quick
    re-compilation;
  * no demo source includes Whisper.inc (demos have no path to lib/);
  * no source spells a constant in two ways (Pascal ignores case).

Adapted from TSteamAPI's tools/project_check.py (Lazarus / Free Pascal twin
and Steam demo checks removed).
Exit code 0 = clean, 1 = problems found.
"""
import os, re, sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NS = "{http://schemas.microsoft.com/developer/msbuild/2003}"
problems = []


def native(base, rel):
    return os.path.normpath(os.path.join(base, *rel.split("\\")))


def source_units(path):
    text = open(path, encoding="latin-1").read()
    return {os.path.normcase(native(os.path.dirname(path), m))
            for m in re.findall(r"\bin\s+'([^']+\.pas)'", text, re.I)}


def package_requires(dpk):
    """Names in the requires clause of a .dpk (lower case)."""
    text = re.sub(r"\{[^}]*\}|\(\*.*?\*\)|//[^\n]*", " ", open(dpk, encoding="latin-1").read(), flags=re.S)
    m = re.search(r"\brequires\b(.*?);", text, re.S | re.I)
    return [n.strip().lower() for n in m.group(1).split(",")] if m else []


def check_group_order(rel, order, tree):
    """Packages after what they require, applications after all packages,
    targets in the order of the Projects list."""
    names = [os.path.splitext(os.path.basename(p))[0] for p in order]
    is_pkg = [os.path.exists(os.path.splitext(p)[0] + ".dpk") for p in order]
    pos = {n.lower(): i for i, n in enumerate(names)}
    for i, p in enumerate(order):
        if is_pkg[i]:
            for req in package_requires(os.path.splitext(p)[0] + ".dpk"):
                if req in pos and pos[req] > i:
                    problems.append(f"{rel}: {names[i]} is listed before {names[pos[req]]}, "
                                    "which it requires - runtime, FMX runtime, design, then applications")
        elif any(is_pkg[i + 1:]):
            problems.append(f"{rel}: application {names[i]} is listed before a package "
                            "- runtime, FMX runtime, design, then applications")
    for t in tree.iter(NS + "Target"):
        if t.get("Name") in ("Build", "Clean", "Make"):
            for c in t.iter(NS + "CallTarget"):
                got = [x.split(":")[0] for x in c.get("Targets").split(";")]
                if got != names:
                    problems.append(f"{rel}: {t.get('Name')} target order {';'.join(got)} differs "
                                    f"from the Projects order {';'.join(names)}")


for dirpath, _, files in os.walk(ROOT):
    if "/." in dirpath or "__history" in dirpath:
        continue
    for f in files:
        if not f.endswith((".dproj", ".groupproj")):
            continue
        path = os.path.join(dirpath, f)
        rel = os.path.relpath(path, ROOT)
        data = open(path, "rb").read()
        if not data.startswith(b"\xef\xbb\xbf"):
            problems.append(f"{rel}: missing UTF-8 BOM")
        try:
            tree = ET.fromstring(data.decode("utf-8-sig"))
        except ET.ParseError as e:
            problems.append(f"{rel}: XML does not parse: {e}")
            continue
        if f.endswith(".groupproj"):
            order = []
            for p in tree.iter(NS + "Projects"):
                if not os.path.exists(native(dirpath, p.get("Include"))):
                    problems.append(f"{rel}: project {p.get('Include')} does not exist")
                order.append(native(dirpath, p.get("Include")))
            check_group_order(rel, order, tree)
            continue
        refs = set()
        for r in tree.iter(NS + "DCCReference"):
            inc = r.get("Include")
            if inc.lower().endswith(".pas"):
                full = native(dirpath, inc)
                if not os.path.exists(full):
                    problems.append(f"{rel}: DCCReference {inc} does not exist")
                refs.add(os.path.normcase(full))
        main = None
        for m in tree.iter(NS + "MainSource"):
            if m.text and m.text.lower().endswith((".dpr", ".dpk")):
                main = native(dirpath, m.text)
                break
        if main is None or not os.path.exists(main):
            problems.append(f"{rel}: main source missing")
            continue
        src = source_units(main)
        for u in sorted(src - refs):
            problems.append(f"{rel}: {os.path.relpath(u, ROOT)} is in {os.path.basename(main)} but not in the .dproj")
        for u in sorted(refs - src):
            problems.append(f"{rel}: {os.path.relpath(u, ROOT)} is in the .dproj but not in {os.path.basename(main)}")

# Demos have no path to lib/ (they link the packages' DCUs), so a demo
# source that includes Whisper.inc fails with F1026 in Delphi.
INC = re.compile(r"\{\$I(?:NCLUDE)?\s+'?Whisper\.inc", re.I)
for dirpath, _, files in os.walk(os.path.join(ROOT, "demos")):
    for f in files:
        if f.lower().endswith((".pas", ".dpr", ".lpr")):
            path = os.path.join(dirpath, f)
            if INC.search(open(path, encoding="latin-1").read()):
                problems.append(f"{os.path.relpath(path, ROOT)}: includes Whisper.inc "
                                "(demos have no path to lib/ - use {$ifdef FPC}{$mode delphi}{$endif})")

# in its own unit is reported.
CONST_DECL = re.compile(r"^\s+([A-Z][A-Z0-9_]*[A-Z0-9])\s*=", re.M)
for top in ("demos", "lib", "fmx", "vcl", "lcl"):
    for dirpath, _, files in os.walk(os.path.join(ROOT, top)):
        for f in files:
            if not f.lower().endswith(".pas"):
                continue
            path = os.path.join(dirpath, f)
            text = re.sub(r"\{[^}]*\}|\(\*.*?\*\)|//[^\n]*|'[^']*'", " ",
                          open(path, encoding="latin-1").read(), flags=re.S)
            spellings = {}
            for tok in set(re.findall(r"\b[A-Za-z_]\w*\b", text)):
                spellings.setdefault(tok.lower(), set()).add(tok)
            for c in sorted(set(CONST_DECL.findall(text))):
                other = spellings.get(c.lower(), set()) - {c}
                if other:
                    problems.append(f"{os.path.relpath(path, ROOT)}: constant {c} is also spelled "
                                    f"{', '.join(sorted(other))} - Pascal ignores case: rename one")

for p in problems:
    print(p)
print(f"{len(problems)} problem(s)")
sys.exit(1 if problems else 0)
