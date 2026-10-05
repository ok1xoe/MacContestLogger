#!/bin/sh
# Extracts the macOS `keyTable` (kVK -> java.awt.event.KeyEvent.VK_*) from OpenJDK's AWTEvent.m
# into Tests/MCLCoreTests/Fixtures/awt-mac-keycodes-jdk21.tsv. VK names are resolved to numbers
# through the JDK 21 fixture awt-vk-codes-jdk21.tsv.
#
# Usage: sh Tools/keys/extract_mac_keytable.sh <path to AWTEvent.m>
# Source: https://github.com/openjdk/jdk/blob/jdk-21+35/src/java.desktop/macosx/native/libawt_lwawt/awt/AWTEvent.m
set -eu
SRC=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VK="$ROOT/Tests/MCLCoreTests/Fixtures/awt-vk-codes-jdk21.tsv"
OUT="$ROOT/Tests/MCLCoreTests/Fixtures/awt-mac-keycodes-jdk21.tsv"
SHA=$(shasum -a 256 "$SRC" | cut -d' ' -f1)
{
  echo "# OpenJDK jdk-21+35 src/java.desktop/macosx/native/libawt_lwawt/awt/AWTEvent.m keyTable (sha256 $SHA)"
  echo "# columns: kVK (hex) <TAB> VK name <TAB> VK code (KeyEvent, JDK 21)"
  awk '
    FNR == NR { if ($0 !~ /^#/) { split($0, f, "\t"); if (!(f[2] in code)) code[f[2]] = f[3] } next }
    /^const keyTable\[\] =/ { inside = 1; next }
    inside && /^};/ { inside = 0 }
    inside && /java_awt_event_KeyEvent_VK_/ {
      line = $0
      sub(/^[ \t]*\{/, "", line)
      split(line, p, ",")
      kvk = p[1]; gsub(/[ \t]/, "", kvk)
      name = p[4]; sub(/^.*java_awt_event_KeyEvent_VK_/, "", name); sub(/\}.*$/, "", name); gsub(/[ \t]/, "", name)
      if (!(name in code)) { print "unknown VK " name > "/dev/stderr"; exit 1 }
      printf "%s\t%s\t%s\n", kvk, name, code[name]
    }
  ' "$VK" "$SRC"
} > "$OUT"
echo "wrote $(grep -vc '^#' "$OUT") rows to $OUT"
