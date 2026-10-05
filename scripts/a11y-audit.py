#!/usr/bin/env python3
"""Static accessibility audit of the SwiftUI / AppKit sources (no dependencies, system Python 3).

    scripts/a11y-audit.py [--root DIR] [--self-test]

It reads `Sources/MacContestLogger` and the shipped language files and prints one finding per line as
`file:line: RULE: message`; the exit status is 1 when there is any finding. It never launches the app and reads
nothing but source files, so it is safe on a locked screen and in CI.

Rules
  A1  `Image(systemName:)` outside `IconButton.swift` is hidden from VoiceOver or labelled (a modifier within the
      next 15 lines): an icon button goes through `IconButton`, a decoration is `.accessibilityHidden(true)`.
  A2  A glyph-only `Text` (one or two characters that are not letters or digits, or a `glyph` variable) has an
      accessibility label within the next 12 lines.
  A3  A `Canvas` has an accessibility modifier (element, label or hidden) within the next 45 lines.
  A4  Every `NSViewRepresentable` file labels its AppKit island (`setAccessibility…`, `accessibilityLabel`,
      `accessibilityHidden`) — the transparent helper views are allowlisted below.
  A5  A custom-drawn `NSView` (it overrides `draw`) has an accessibility role or children.
  A6  `IconButton` is never given an empty label.
  A7  Every window of `WindowsModel.kotlinOrder` (and the multiplier grids, the main window, the dialogs, Settings)
      is built from a view that has the font stepper (`WindowTopBar` / `ToolWindowShell`), and the stepper itself
      labels both buttons and the group with `tr(…)`.
  A8  Every `tr("…")` literal of a spoken text (`AccessibilityText.swift`, an accessibility label, a `help`, an
      `IconButton` label) exists in `lang_en.json` and `lang_de.json`.

An exception goes in `ALLOW` with the reason; `--self-test` checks that every rule fires on a known bad snippet and
that an unused allowlist entry is reported (so exceptions cannot rot); A7, A8 and the allowlist check run on a
throw-away tree. A4/A5 are file-level checks and A1 accepts any accessibility modifier of the statement: heuristics.
"""
import json
import os
import re
import sys

# (relative path, rule, text that must occur on the finding's line or the struct name) -> reason
ALLOW = {
    ("Views/WindowGeometry.swift", "A4", "WindowAccessor"):
        "a zero-size helper that only reads the hosting NSWindow; it draws nothing",
    ("Views/TuningWheel.swift", "A4", "TuningWheelArea"):
        "a transparent area whose hitTest is nil; it only reports where the entry panel is",
    ("Views/LogPrintView.swift", "A5", "LogPrintView"):
        "the print view of the print operation: it is never shown in a window, the printed page is not interactive",
    ("Spots/FlowLayout.swift", "A4", "SecondaryClickArea"):
        "a transparent overlay that adds a right click to a view that is labelled itself",
}

SOURCE_DIR = "Sources/MacContestLogger"
LANG_DIR = "Sources/MCLCore/Resources/i18n"
MODIFIER = re.compile(r"\.accessibility(Label|Hidden|Element|Value)\b|setAccessibility(Label|Element)")


class Finding:
    def __init__(self, path, line, rule, message):
        self.path, self.line, self.rule, self.message = path, line, rule, message

    def __str__(self):
        return f"{self.path}:{self.line}: {self.rule}: {self.message}"


def read_lines(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read().split("\n")


def swift_files(root):
    base = os.path.join(root, SOURCE_DIR)
    for folder, _, names in os.walk(base):
        for name in sorted(names):
            if name.endswith(".swift"):
                yield os.path.join(folder, name)


def strip_comment(line):
    index = line.find("//")
    return line if index < 0 else line[:index]


def statement_lines(lines, start):
    """The statement that begins on `start`: its own lines while a bracket is open, then the modifier chain that
    follows (lines starting with `.`) and the closing brackets of an enclosing closure that precede it."""
    out = []
    balance = 0
    for index in range(start, min(start + 80, len(lines))):
        text = strip_comment(lines[index])
        stripped = text.strip()
        if index > start and balance <= 0 and not (stripped.startswith(".") or stripped[:1] in ("}", ")")):
            break
        if not stripped and index > start:
            break
        out.append(text)
        balance += sum(text.count(c) for c in "({[") - sum(text.count(c) for c in ")}]")
    return out


def window_has(lines, start, count=0, pattern=MODIFIER):
    return any(pattern.search(l) for l in statement_lines(lines, start))


def audit_file(rel, lines, used):
    findings = []

    def allowed(rule, text):
        for key, _ in ALLOW.items():
            if key[0] == rel and key[1] == rule and key[2] in text:
                used.add(key)
                return True
        return False

    in_icon = rel.endswith("Views/IconButton.swift")
    is_audit_text = False
    for number, raw in enumerate(lines):
        line = strip_comment(raw)
        shown = number + 1
        # A1
        if "Image(systemName:" in line and not in_icon:
            if not window_has(lines, number, 16) and not allowed("A1", line):
                findings.append(Finding(rel, shown, "A1", "Image(systemName:) without a label or accessibilityHidden"))
        # A2
        match = re.search(r'Text\(verbatim: "([^"]*)"\)', line)
        glyph = False
        if match:
            text = match.group(1)
            if 0 < len(text) <= 2 and not any(c.isalnum() for c in text):
                glyph = True
        if re.search(r"Text\(verbatim: glyph\)", line):
            glyph = True
        if glyph and not window_has(lines, number, 13) and not allowed("A2", line):
            findings.append(Finding(rel, shown, "A2", "glyph-only Text without an accessibility label"))
        # A3
        if re.search(r"\bCanvas\s*\{", line) or re.search(r"\bCanvas\s*\(", line):
            if not window_has(lines, number, 46) and not allowed("A3", line):
                findings.append(Finding(rel, shown, "A3", "Canvas without an accessibility modifier"))
        # A6
        if re.search(r'IconButton\([^)]*label:\s*""', line):
            findings.append(Finding(rel, shown, "A6", "IconButton with an empty label"))
    text = "\n".join(lines)
    # A4
    for number, raw in enumerate(lines):
        match = re.match(r"\s*(?:private\s+)?struct\s+(\w+)\s*:\s*NSViewRepresentable", raw)
        if match and not re.search(r"setAccessibility|accessibilityLabel|accessibilityHidden", text):
            if not allowed("A4", match.group(1)):
                findings.append(Finding(rel, number + 1, "A4", f"{match.group(1)} (AppKit island) has no accessibility"))
    # A5
    for number, raw in enumerate(lines):
        match = re.match(r"\s*(?:final\s+)?class\s+(\w+)\s*:\s*NSView\b", raw)
        if match and re.search(r"override func draw\(", text):
            if not re.search(r"setAccessibilityRole|accessibilityChildren", text) and not allowed("A5", match.group(1)):
                findings.append(Finding(rel, number + 1, "A5",
                                        f"{match.group(1)} draws itself without an accessibility role or children"))
    return findings


def kotlin_order(root):
    text = "\n".join(read_lines(os.path.join(root, "Sources/MCLAppModel/WindowsModel.swift")))
    match = re.search(r"kotlinOrder: \[String\] = \[(.*?)\]", text, re.S)
    return re.findall(r'"([^"]+)"', match.group(1)) if match else []


def audit_steppers(root):
    findings = []
    base = os.path.join(root, SOURCE_DIR)
    stepper = {}
    ids = {}
    for path in swift_files(root):
        rel = os.path.relpath(path, base)
        text = "\n".join(read_lines(path))
        stepper[rel] = "WindowTopBar(" in text or "ToolWindowShell(" in text or "WindowFontStepper(" in text
        for match in re.finditer(r'static let id = "([^"]+)"', text):
            ids[match.group(1)] = rel
        if "struct MultGridWindowView" in text:
            ids["mult"] = rel
    # windows that are not a `static let id` view but are scenes of their own
    fixed = {
        "log": "Views/LogTableView.swift", "defeditor": "Views/DefinitionEditorWindow.swift",
        "profiles": "Views/ProfilesWindow.swift", "main": "Views/MainWindowView.swift",
        "entry-vfob": "Views/EntryVfoBWindow.swift", "settings": "Settings/SettingsWindow.swift",
        "dialogs": "Views/DialogWindow.swift", "worldmap-dxcc": ids.get("worldmap", "Tools/WorldMapWindow.swift"),
    }
    required = list(kotlin_order(root)) + ["mult", "main", "entry-vfob", "settings", "dialogs"]
    for window in required:
        rel = fixed.get(window) or ids.get(window)
        if rel is None:
            findings.append(Finding("Sources/MCLAppModel/WindowsModel.swift", 1, "A7",
                                    f"window '{window}' has no view with its id"))
        elif not stepper.get(rel, False):
            findings.append(Finding(SOURCE_DIR + "/" + rel, 1, "A7", f"window '{window}' has no font stepper"))
    # the stepper labels itself
    stepper_path = os.path.join(base, "Views/WindowFontStepper.swift")
    if os.path.exists(stepper_path):
        text = "\n".join(read_lines(stepper_path))
        for key in ("Zmenšit písmo", "Zvětšit písmo", "Velikost písma"):
            if f'tr("{key}")' not in text:
                findings.append(Finding(SOURCE_DIR + "/Views/WindowFontStepper.swift", 1, "A7",
                                        f"the stepper does not label with tr(\"{key}\")"))
    return findings


SPOKEN_LINE = re.compile(r"accessibilityLabel|setAccessibilityLabel|accessibilityHint|\.help\(|IconButton\(|label:|accessibilityText:|"
                         r"accessibilityValue")


def language_keys(root):
    keys = {}
    for code in ("en", "de"):
        with open(os.path.join(root, LANG_DIR, f"lang_{code}.json"), encoding="utf-8") as handle:
            keys[code] = set(json.load(handle).keys())
    return keys


def audit_keys(root):
    findings = []
    keys = language_keys(root)
    literal = re.compile(r'(?:\btr|\.translate)\(\s*"((?:[^"\\]|\\.)*)"')
    targets = []
    for path in swift_files(root):
        targets.append((path, os.path.relpath(path, os.path.join(root, SOURCE_DIR))))
    targets.append((os.path.join(root, "Sources/MCLAppModel/AccessibilityText.swift"), "../MCLAppModel/AccessibilityText.swift"))
    for path, rel in targets:
        everything = rel.endswith("AccessibilityText.swift")
        lines = read_lines(path)
        if everything:
            # whole-file: a literal may sit on the line after `translate(`
            body = "\n".join(strip_comment(l) for l in lines)
            hits = [(body.count("\n", 0, m.start()) + 1, m.group(1)) for m in literal.finditer(body)]
        else:
            hits = []
            for number, raw in enumerate(lines):
                line = strip_comment(raw)
                if SPOKEN_LINE.search(line):
                    hits.extend((number + 1, m.group(1)) for m in literal.finditer(line))
        for number, raw_key in hits:
            key = json.loads('"' + raw_key + '"')
            for code, known in keys.items():
                if key not in known:
                    findings.append(Finding(rel, number, "A8", f'tr("{key}") is missing in lang_{code}.json'))
    return findings


def run(root):
    used = set()
    findings = []
    for path in swift_files(root):
        rel = os.path.relpath(path, os.path.join(root, SOURCE_DIR))
        findings.extend(audit_file(rel, read_lines(path), used))
    findings.extend(audit_steppers(root))
    findings.extend(audit_keys(root))
    for key, reason in ALLOW.items():
        if key not in used:
            findings.append(Finding("scripts/a11y-audit.py", 1, "ALLOW",
                                    f"unused allowlist entry {key[0]} {key[1]} {key[2]} ({reason})"))
    return findings


def self_test():
    bad = {
        "A1": ["Image(systemName: \"trash\")", "Text(\"x\")"],
        "A2": ['Text(verbatim: "▲")'],
        "A3": ["Canvas { context, size in", "}"],
        "A6": ['IconButton(symbol: "x", label: "") { }'],
    }
    ok = {
        "A1": ["Image(systemName: \"trash\")", ".accessibilityHidden(true)"],
        "A2": ['Text(verbatim: "▲")', ".accessibilityLabel(\"up\")"],
        "A3": ["Canvas { context, size in", "}", ".accessibilityElement(children: .ignore)"],
    }
    failures = []
    for rule, lines in bad.items():
        found = [f.rule for f in audit_file("Fake/X.swift", lines + [""] * 3, set())]
        if rule not in found:
            failures.append(f"{rule} did not fire on its bad snippet")
    for rule, lines in ok.items():
        found = [f.rule for f in audit_file("Fake/X.swift", lines + [""] * 3, set())]
        if rule in found:
            failures.append(f"{rule} fired on its good snippet")
    a4 = audit_file("Fake/X.swift", ["struct Y: NSViewRepresentable {", "}"], set())
    if "A4" not in [f.rule for f in a4]:
        failures.append("A4 did not fire")
    a5 = audit_file("Fake/X.swift", ["final class Z: NSView {", "override func draw(_ r: NSRect) {}", "}"], set())
    if "A5" not in [f.rule for f in a5]:
        failures.append("A5 did not fire")
    failures.extend(self_test_tree())
    for failure in failures:
        print("self-test: " + failure)
    print("self-test: " + ("FAILED" if failures else "ok"))
    return 1 if failures else 0


def self_test_tree():
    """A7, A8 and the unused-allowlist check on a throw-away source tree (a window without a stepper, a spoken key
    that no language file has)."""
    import tempfile
    import shutil
    root = tempfile.mkdtemp(prefix="a11y-selftest-")
    failures = []
    try:
        def write(rel, text):
            path = os.path.join(root, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)
        write("Sources/MCLAppModel/WindowsModel.swift", 'kotlinOrder: [String] = ["ghost", "bare"]\n')
        write("Sources/MCLAppModel/AccessibilityText.swift", 'let x = translator.translate("no such key")\n')
        write("Sources/MacContestLogger/Views/BareWindow.swift", 'struct BareWindow { static let id = "bare" }\n')
        write("Sources/MacContestLogger/Views/WindowFontStepper.swift", "struct S {}\n")
        for code in ("en", "de"):
            write(f"Sources/MCLCore/Resources/i18n/lang_{code}.json", "{}")
        rules = [f.rule for f in run(root)]
        for rule in ("A7", "A8", "ALLOW"):
            if rule not in rules:
                failures.append(f"{rule} did not fire on the throw-away tree")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    return failures


def main():
    args = sys.argv[1:]
    if "--self-test" in args:
        return self_test()
    root = os.getcwd()
    if "--root" in args:
        root = args[args.index("--root") + 1]
    findings = run(root)
    for finding in findings:
        print(finding)
    print(f"a11y-audit: {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
