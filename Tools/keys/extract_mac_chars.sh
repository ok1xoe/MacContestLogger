#!/bin/sh
# Extracts the character branch of `NsCharToJavaVirtualKeyCode` and the modifier-key table of
# `NsKeyModifiersToJavaKeyInfo` from OpenJDK's AWTEvent.m into
# Tests/MCLCoreTests/Fixtures/awt-mac-chars-jdk21.tsv (factual numeric mapping only, no source code).
# VK names are resolved to numbers through awt-vk-codes-jdk21.tsv; the script fails when the source
# is not the jdk-21+35 revision (its SHA-256 is checked; another revision has to be re-read by hand).
#
# Usage: sh Tools/keys/extract_mac_chars.sh <path to AWTEvent.m>
# Source: https://github.com/openjdk/jdk/blob/jdk-21+35/src/java.desktop/macosx/native/libawt_lwawt/awt/AWTEvent.m
set -eu
SRC=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VK="$ROOT/Tests/MCLCoreTests/Fixtures/awt-vk-codes-jdk21.tsv"
OUT="$ROOT/Tests/MCLCoreTests/Fixtures/awt-mac-chars-jdk21.tsv"
SHA=$(shasum -a 256 "$SRC" | cut -d' ' -f1)

# The RULE rows below were read by hand from this exact revision; refuse any other file.
EXPECTED=b478c7e80024525964f6ffe3f89fa5d0aabab02b5bc4d36aacca84c743424bb8
if [ "$SHA" != "$EXPECTED" ]; then
  echo "unexpected AWTEvent.m (sha256 $SHA, expected $EXPECTED): re-read the rules by hand" >&2
  exit 1
fi

{
  echo "# OpenJDK jdk-21+35 src/java.desktop/macosx/native/libawt_lwawt/awt/AWTEvent.m (sha256 $SHA)"
  echo "# NsCharToJavaVirtualKeyCode (character branch) and NsKeyModifiersToJavaKeyInfo (flagsChanged)."
  echo "# Input fields (JDK 21.0.2 sun.lwawt.macosx.CPlatformResponder.handleKeyEvent): the VK comes from the first"
  echo "# UTF-16 unit of NSEvent.charactersIgnoringModifiers (CHAR_UNDEFINED 0xFFFF when empty); the event is a dead"
  echo "# key when NSEvent.characters is empty (not nil); a dead key whose layout character is not in DEAD drops the"
  echo "# event (no KEY_PRESSED/KEY_RELEASED). Order: DEAD (dead key only), letter, decimal digit, keyTable by kVK."
  echo "# RULE LETTER: NSCharacterSet.letterCharacterSet; tolower() -- ASSUMED C locale (ASCII only): the real fold"
  echo "#   depends on the JVM launch environment (LANG; a UTF-8 locale folds non-ASCII too); a..z -> VK_A + offset,"
  echo "#   other letters -> 0x01000000 + lower (VK_A + (lower - 'a') + 0x01000000 + 32); location STANDARD."
  echo "# RULE DIGIT: NSCharacterSet.decimalDigitCharacterSet, ch - '0' in 0..9; NUMPAD when NSNumericPadKeyMask"
  echo "#   (1<<21) is set and 81 < kVK < 93 -> VK_NUMPAD0 + offset, location NUMPAD; else VK_0 + offset, STANDARD."
  echo "# MODIFIER rows in table order: first row whose mask changed (previous flags XOR flags) wins; location LEFT/RIGHT"
  echo "#   by kVK, else STANDARD, except Alternate, which then continues with VK_ALT/STANDARD/KEY_PRESSED kept;"
  echo "#   phase PRESSED when the mask is set in the new flags, else RELEASED."
  echo "# columns: LOCATION kVK postsTyped location | DEAD unicode VK-name VK-code | MODIFIER mask-name mask left right VK-name VK-code | RULE name values"
  printf 'RULE\tLETTER_EXTENDED_BASE\t0x01000000\n'
  printf 'RULE\tLETTER_EXTENDED_ADD\t32\n'
  printf 'RULE\tNUMPAD_KVK_EXCLUSIVE\t81\t93\n'
  printf 'RULE\tNUMPAD_FLAG\t0x200000\n'
  awk '
    function vk(name) {
      if (!(name in code)) { print "unknown VK " name > "/dev/stderr"; exit 1 }
      return code[name]
    }
    function mask(name) {
      if (name == "NSAlphaShiftKeyMask") return "0x10000"
      if (name == "NSShiftKeyMask") return "0x20000"
      if (name == "NSControlKeyMask") return "0x40000"
      if (name == "NSAlternateKeyMask") return "0x80000"
      if (name == "NSCommandKeyMask") return "0x100000"
      if (name == "NSHelpKeyMask") return "0x400000"
      print "unknown mask " name > "/dev/stderr"; exit 1
    }
    FNR == NR { if ($0 !~ /^#/) { split($0, f, "\t"); if (!(f[2] in code)) code[f[2]] = f[3] } next }
    /^const keyTable\[\] =/ { part = "key"; next }
    /^static const struct CharToVKEntry charToDeadVKTable\[\] =/ { part = "dead"; next }
    /^const nsKeyToJavaModifierTable\[\] =/ { part = "mod"; n = 0; next }
    part != "" && /^};/ { part = ""; next }
    part == "key" && /java_awt_event_KeyEvent_VK_/ {
      line = $0; sub(/^[ \t]*\{/, "", line); split(line, p, ",")
      kvk = p[1]; gsub(/[ \t]/, "", kvk)
      typed = p[2]; gsub(/[ \t]/, "", typed)
      loc = p[3]; gsub(/[ \t]/, "", loc)
      if (loc == "KL_STANDARD") loc = "STANDARD"; else if (loc == "KL_NUMPAD") loc = "NUMPAD"; else if (loc == "KL_UNKNOWN") loc = "UNKNOWN"
      else { print "unknown location " loc > "/dev/stderr"; exit 1 }
      printf "LOCATION\t%s\t%s\t%s\n", kvk, typed, loc
    }
    part == "dead" && /java_awt_event_KeyEvent_VK_/ {
      line = $0; sub(/^[ \t]*\{/, "", line); split(line, p, ",")
      uc = p[1]; gsub(/[ \t]/, "", uc)
      name = p[2]; sub(/^.*java_awt_event_KeyEvent_VK_/, "", name); sub(/\}.*$/, "", name); gsub(/[ \t]/, "", name)
      printf "DEAD\t%s\t%s\t%s\n", uc, name, vk(name)
    }
    part == "mod" {
      line = $0; sub(/\/\/.*$/, "", line); gsub(/[ \t]/, "", line)
      if (line == "{") { n = 0; next }
      if (line == "},") {
        if (n != 6) { print "modifier row with " n " fields" > "/dev/stderr"; exit 1 }
        name = f6; sub(/^java_awt_event_KeyEvent_VK_/, "", name)
        printf "MODIFIER\t%s\t%s\t%s\t%s\t%s\t%s\n", f1, mask(f1), f2, f3, name, vk(name)
        next
      }
      if (line == "" || line ~ /^\{0,/) next
      sub(/,$/, "", line)
      n++
      if (n == 1) f1 = line; else if (n == 2) f2 = line; else if (n == 3) f3 = line; else if (n == 6) f6 = line
    }
  ' "$VK" "$SRC"
} > "$OUT"
echo "wrote $(grep -vc '^#' "$OUT") rows to $OUT"
