#!/usr/bin/env python3
"""Static translation audit of the Swift sources (no dependencies, system Python 3).

    scripts/i18n-audit.py [--root DIR] [--all]

The UI texts are Czech in the code and translated by Sources/MCLCore/Resources/i18n/lang_<code>.json (key = the
Czech text). The script reads Sources/MCLCore, Sources/MCLAppModel and Sources/MacContestLogger (comments skipped)
and prints one finding per line as `file:line: KIND: text`; the exit status is 1 when there is any finding of the
first three kinds, which `SourceTranslationAuditTests` (MCLCoreTests) also enforces:

  KEY      a literal key handed to the translator (`tr`, `translate`, `ContestMessage`, `status.show`, a `+` chain of
           literals) is missing in lang_en.json or lang_de.json, or is built with string interpolation;
  VIEW     in the app's views a Czech literal goes straight to a visible text (`Text`, `Button`, a tooltip, an
           accessibility label, a menu item, a Settings form part…) without `tr`;
  VERBATIM a Czech literal is shown as is (`.verbatim(…)`, `showVerbatim(…)`).

A literal is Czech when it has Czech diacritics or when it is a key of lang_en.json with a different English text
("Smazat", "Celkem", "Heslo"); so the rules know the Czech words without diacritics and leave English, numbers and
codes alone.

With `--all` it also lists, for review, every other literal with Czech diacritics that is not a key of lang_en.json
(REVIEW): mostly error and log texts, file contents and data, but also texts that reach the UI through a constant or
a helper — check where such a text is shown before translating it. See docs/translations.md.
"""
import json
import os
import re
import sys

DIACRITICS = set("áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ")
DIRS = ["MCLCore", "MCLAppModel", "MacContestLogger"]
TRANSLATOR = re.compile(r'(?<![A-Za-z_])(tr|translate|ContestMessage|show)\(\s*$')
VISIBLE = re.compile(
    r'(?:Text\((?:verbatim:\s*)?|Button\(|Label\(|Toggle\(|Picker\(|Menu\(|TextField\(|SecureField\(|Section\('
    r'|\.help\(|\.navigationTitle\(|accessibility(?:Label|Hint|Value)\((?:Text\((?:verbatim:\s*)?)?'
    r'|messageText\s*=\s*|informativeText\s*=\s*|addButton\(withTitle:\s*|NSMenuItem\(title:\s*'
    r'|toolTip\s*=\s*|addItem\(menu,\s*|ToolField\(label:\s*'
    r'|Settings(?:Group|Field|Caption|Checkbox|Radio|Button|Text|DeleteButton)\((?:title:|caption:|label:|help:)?\s*'
    r')(?:[^()\n]*?[?:]\s*)?$')
VERBATIM = re.compile(r'(?:\.verbatim|showVerbatim)\(\s*$')
# The same exceptions as SourceTranslationAuditTests.allowed.
ALLOWED = {
    ("MacContestLogger/MacContestLoggerApp.swift", "Aplikaci nelze spustit: chybí její zdroje."),
    ("MacContestLogger/MacContestLoggerApp.swift", "Ukončit"),
    ("MacContestLogger/AppHost.swift", "Ukončit"),
}


def literals(src):
    """(line, text, interpolated, before, after) of every string literal outside comments; `before`/`after` are the
    surrounding code without comments and with every literal emptied."""
    out, masked, pending = [], [], []
    i, n, line = 0, len(src), 1

    def tail():
        t = "".join(masked[-200:])
        cut = max(t.rfind("{"), t.rfind("}"), t.rfind(";"))
        return t[cut + 1:].replace("\n", " ")

    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            depth = 0
            while i < n:
                if src.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                    continue
                if src.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                    if depth == 0:
                        break
                    continue
                if src[i] == "\n":
                    line += 1
                i += 1
            continue
        hashes = 0
        while i + hashes < n and src[i + hashes] == "#":
            hashes += 1
        if i + hashes < n and src[i + hashes] == '"':
            start = line
            multi = src.startswith('"""', i + hashes)
            close = ('"""' if multi else '"') + "#" * hashes
            esc = "\\" + "#" * hashes
            j = i + hashes + (3 if multi else 1)
            text, interp = [], False
            while j < n and not src.startswith(close, j):
                if src.startswith(esc, j):
                    k = j + len(esc)
                    ch = src[k] if k < n else ""
                    if ch == "(":
                        interp, depth, m = True, 0, k
                        while m < n:
                            if src[m] == "(":
                                depth += 1
                            elif src[m] == ")":
                                depth -= 1
                                if depth == 0:
                                    break
                            elif src[m] == '"':
                                m += 1
                                while m < n and src[m] != '"':
                                    m += 2 if src[m] == "\\" else 1
                            m += 1
                        text.append("\\(" + src[k + 1:m] + ")")
                        j = m + 1
                        continue
                    if ch == "u" and src.startswith("{", k + 1):
                        end = src.find("}", k)
                        text.append(chr(int(src[k + 2:end], 16)))
                        j = end + 1
                        continue
                    if ch == "\n":
                        line += 1
                        j = k + 1
                        while j < n and src[j] in " \t":
                            j += 1
                        continue
                    text.append({"n": "\n", "t": "\t", "r": "\r", "0": "\0"}.get(ch, ch))
                    j = k + 1
                    continue
                if src[j] == "\n":
                    if not multi:
                        break
                    line += 1
                text.append(src[j])
                j += 1
            value = "".join(text)
            if multi:
                if value.startswith("\n"):
                    value = value[1:]
                if "\n" in value:
                    value = value[:value.rfind("\n")]
            before = tail()
            masked.extend('""')
            pending.append((start, value, interp, before, len(masked)))
            i = j + len(close)
            continue
        masked.append(c)
        i += 1
    text = "".join(masked)
    for start, value, interp, before, end in pending:
        out.append((start, value, interp, before, text[end:end + 120].lstrip(" \n\t")[:80]))
    return out


def audit(root, show_all):
    i18n = os.path.join(root, "Sources/MCLCore/Resources/i18n")
    en = json.load(open(os.path.join(i18n, "lang_en.json"), encoding="utf-8"))
    de = json.load(open(os.path.join(i18n, "lang_de.json"), encoding="utf-8"))
    findings, review = [], []
    for top in DIRS:
        base = os.path.join(root, "Sources", top)
        for dirpath, _, files in os.walk(base):
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, os.path.join(root, "Sources"))
                lits = literals(open(path, encoding="utf-8").read())
                k = 0
                while k < len(lits):
                    line, value, interp, before, after = lits[k]
                    place = "%s:%d" % (rel, line)
                    if TRANSLATOR.search(before):
                        key, last_after = value, after
                        while k + 1 < len(lits) and last_after.startswith("+") \
                                and lits[k + 1][3].rstrip().endswith("+"):
                            k += 1
                            key += lits[k][1]
                            interp = interp or lits[k][2]
                            last_after = lits[k][4]
                        if interp:
                            findings.append("%s: KEY: built with interpolation: %s" % (place, key))
                        elif last_after[:1] in (",", ")"):
                            missing = [c for c, m in (("en", en), ("de", de)) if key not in m]
                            if missing:
                                findings.append("%s: KEY: missing in %s: %s" % (place, "/".join(missing), key))
                        k += 1
                        continue
                    # Czech: diacritics, or a text the shipped English translates to something else.
                    czech = any(ch in DIACRITICS for ch in value) or (value in en and en[value] != value)
                    if czech and (rel, value) not in ALLOWED:
                        if VERBATIM.search(before):
                            findings.append("%s: VERBATIM: %s" % (place, value))
                        elif rel.startswith("MacContestLogger/") and VISIBLE.search(before):
                            findings.append("%s: VIEW: %s" % (place, value))
                        elif value not in en:
                            review.append("%s: REVIEW: %s" % (place, value.replace("\n", "\\n")[:120]))
                    k += 1
    for f in findings:
        print(f)
    if show_all:
        for r in review:
            print(r)
    print("%d findings%s" % (len(findings), (", %d literals to review" % len(review)) if show_all else ""),
          file=sys.stderr)
    return 1 if findings else 0


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    show_all = "--all" in argv
    if "--root" in argv:
        root = argv[argv.index("--root") + 1]
    return audit(root, show_all)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
