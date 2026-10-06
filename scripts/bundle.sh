#!/usr/bin/env bash
# Assembles MacContestLogger.app (ad-hoc signed by default, without a sandbox) and optionally a DMG.
#
#   scripts/bundle.sh [--config debug|release] [--version vX.Y.Z] [--file-version NAME] [--universal] [--dmg]
#                     [--skip-build] [--out DIR] [--sign IDENTITY [--entitlements FILE] [--timestamp]]
#
# Steps: `swift build --product MacContestLogger` → Contents/MacOS, Info.plist from packaging/Info.plist.in
# (`plutil -lint`), every SwiftPM resource bundle of the app's targets into Contents/Resources (the app reads them
# from there, see `CoreResources`), `codesign -s -` + `codesign --verify`, and finally `MacContestLogger --self-check`
# (resource check without a window; exit 1 = the app would start without its resources). Writes only into --out
# (default build/app/).
#
# --universal: one build per architecture (arm64-apple-macosx14.0 and x86_64-apple-macosx14.0), the resource
# bundles of both must be identical (`diff -r`, a difference = error), the executables are joined with `lipo -create`
# (`lipo -archs` must say `x86_64 arm64`). A DMG is then named MacContestLogger-<file version>-macos-universal.dmg,
# is checked with `hdiutil verify` and gets a `<dmg>.sha256` next to it (`shasum -c` format). Without --universal
# nothing changes. --file-version overrides only the version in the DMG file name (CI: `dev-<sha7>` for builds
# that are not from a tag; the bundle version stays 0.0.1).
#
# Signing. Without --sign (local, dev and pull-request builds) the app is ad-hoc signed (`codesign --deep -s -`)
# exactly as before and the DMG is not signed. With --sign IDENTITY (a "Developer ID Application" identity, its
# SHA-1 hash, or `-` for an ad-hoc dry run of the same path) the app gets the hardened runtime and the
# entitlements of --entitlements (default packaging/MacContestLogger.entitlements): nested code is signed inside-out
# (any Mach-O file or code bundle under Contents/ other than the main executable; today there is none — the SwiftPM
# resource bundle holds only data), then the app itself, without --deep. --timestamp adds a secure timestamp from
# Apple (required for notarization; ignored for `-`). The DMG is signed with the same identity (not for `-`).
# Notarization and stapling are left to the caller (.github/workflows/release.yml), since they need Apple's service.
#
# Entitlements (packaging/MacContestLogger.entitlements; a plist has no comments, so the reasons are here):
# - com.apple.security.device.audio-input: the hardened runtime blocks the microphone without it — voice keyer
#   recording, contest recording, the CW reader and the waterfall read the input via AVAudioEngine.
# - Nothing else, on purpose: no library-validation or JIT exceptions (the app loads no non-system dylib, uses no
#   dlopen and no JIT; resource bundles are data only), no Apple Events (no NSAppleScript/osascript). Child
#   processes (rigctld, plugin scripts, `/bin/sh` fallback) need no entitlement under the hardened runtime; serial
#   ports (termios/IOKit) and the network need none outside the sandbox.
# - The app is NOT sandboxed (no com.apple.security.app-sandbox): a sandbox would block arbitrary serial devices,
#   spawning rigctld and user plugin scripts, and reading the reference data outside the container.
#
# App Transport Security in Info.plist (a plist has no comments, so the reasons are here):
# - NSAllowsArbitraryLoads: parity with the JVM app, which loads any URL the user types in — a scoreboard URL
#   (ScorePoster) or a definition-update base URL may be plain http://. ATS governs only URLSession/CFNetwork
#   HTTP(S); MQTT, UDP and plain TCP sockets (cluster sync, N1MM, WSJT-X, rigctld, DX cluster) are not affected by it.
# - NSExceptionDomains keep full ATS strictness (HTTPS only, NSIncludesSubdomains, no insecure loads) for the
#   services the app calls itself (`git grep -hoE "https?://[a-zA-Z0-9.-]+" Sources`):
#   - hamqth.com              — HamQthClient (www.hamqth.com/xml.php, callbook lookup)
#   - qrz.com                 — QrzClient (xmldata.qrz.com, callbook lookup)
#   - clublog.org             — ClubLogClient (realtime upload)
#   - contestonlinescore.com  — ScorePoster / AppConfig default scoreboard URL
#   - hamscore.com           — built-in scoreboard preset (https://hamscore.com/postxml/)
#   The plain-HTTP scoreboard presets (http://scoredistributor.net, http://contest.run) get no entry of their own:
#   they rely on NSAllowsArbitraryLoads above, like any other user-typed http:// scoreboard URL.
#   - supercheckpartial.com   — ScpDownloader (www.supercheckpartial.com/MASTER.SCP)
#   - reversebeacon.net       — RbnLink (www.reversebeacon.net spot lookup)
#   - raw.githubusercontent.com — DefinitionUpdater (contest definition updates)
#   No entry for URLs only opened in the browser (github.com help, www.qrz.com/db, www.hamqth.com/<call>) —
#   ATS does not apply there.
#   Not used on purpose: NSAllowsLocalNetworking, NSAllowsArbitraryLoadsInWebContent, NSAllowsArbitraryLoadsForMedia.
set -euo pipefail

CONFIG=release
VERSION_ARG=""
FILE_VERSION_ARG=""
UNIVERSAL=0
DMG=0
SKIP_BUILD=0
OUT=build/app
SIGN_IDENTITY=""
ENTITLEMENTS=""
TIMESTAMP=0

usage() {
  echo "usage: $0 [--config debug|release] [--version vX.Y.Z] [--file-version NAME] [--universal] [--dmg] [--skip-build] [--out DIR] [--sign IDENTITY [--entitlements FILE] [--timestamp]]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || usage; CONFIG="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || usage; VERSION_ARG="$2"; shift 2 ;;
    --file-version) [ $# -ge 2 ] || usage; FILE_VERSION_ARG="$2"; shift 2 ;;
    --universal) UNIVERSAL=1; shift ;;
    --dmg) DMG=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --out) [ $# -ge 2 ] || usage; OUT="$2"; shift 2 ;;
    --sign) [ $# -ge 2 ] || usage; SIGN_IDENTITY="$2"; shift 2 ;;
    --entitlements) [ $# -ge 2 ] || usage; ENTITLEMENTS="$2"; shift 2 ;;
    --timestamp) TIMESTAMP=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

case "$CONFIG" in
  debug|release) ;;
  *) echo "--config must be debug or release, got '$CONFIG'" >&2; exit 2 ;;
esac

# Version rules (v optional, 1 to 3 numbers, first at least 1, a suffix only in the file name) live in
# scripts/release-version.sh, the single source. Without --version: 0.0.1.
VERSION=0.0.1
FILE_VERSION=0.0.1
if [ -n "$VERSION_ARG" ]; then
  if ! DERIVED="$("$(dirname "$0")/release-version.sh" branch local 0000000 "$VERSION_ARG")"; then
    echo "--version '$VERSION_ARG' rejected" >&2
    exit 2
  fi
  VERSION="$(echo "$DERIVED" | sed -n 's/^bundleVersion=//p')"
  FILE_VERSION="$(echo "$DERIVED" | sed -n 's/^fileVersion=//p')"
fi

if [ -n "$FILE_VERSION_ARG" ]; then
  if ! [[ "$FILE_VERSION_ARG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "--file-version '$FILE_VERSION_ARG': only letters, digits, '.', '_' and '-' are allowed" >&2
    exit 2
  fi
  FILE_VERSION="$FILE_VERSION_ARG"
fi

if [ -z "$SIGN_IDENTITY" ] && { [ -n "$ENTITLEMENTS" ] || [ "$TIMESTAMP" -eq 1 ]; }; then
  echo "--entitlements and --timestamp need --sign" >&2
  exit 2
fi
if [ -n "$ENTITLEMENTS" ] && [ ! -f "$ENTITLEMENTS" ]; then
  echo "--entitlements '$ENTITLEMENTS': no such file" >&2
  exit 2
fi
if [ -n "$ENTITLEMENTS" ]; then
  ENTITLEMENTS="$(cd "$(dirname "$ENTITLEMENTS")" && pwd)/$(basename "$ENTITLEMENTS")"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ -n "$SIGN_IDENTITY" ] && [ -z "$ENTITLEMENTS" ]; then
  ENTITLEMENTS="$ROOT/packaging/MacContestLogger.entitlements"
fi

ARM_TRIPLE=arm64-apple-macosx14.0
X86_TRIPLE=x86_64-apple-macosx14.0
# One scratch directory per architecture: with the newer SwiftPM build system both triples would otherwise write
# into the same products directory (the second build overwrites the first).
SCRATCH_ARM=.build/universal-arm64
SCRATCH_X86=.build/universal-x86_64
if [ "$UNIVERSAL" -eq 1 ]; then
  if [ "$SKIP_BUILD" -eq 0 ]; then
    swift build -c "$CONFIG" --product MacContestLogger --triple "$ARM_TRIPLE" --scratch-path "$SCRATCH_ARM"
    swift build -c "$CONFIG" --product MacContestLogger --triple "$X86_TRIPLE" --scratch-path "$SCRATCH_X86"
  fi
  BIN_ARM="$(swift build -c "$CONFIG" --triple "$ARM_TRIPLE" --scratch-path "$SCRATCH_ARM" --show-bin-path)"
  BIN_X86="$(swift build -c "$CONFIG" --triple "$X86_TRIPLE" --scratch-path "$SCRATCH_X86" --show-bin-path)"
  for d in "$BIN_ARM" "$BIN_X86"; do
    if [ ! -x "$d/MacContestLogger" ]; then
      echo "missing $d/MacContestLogger (build it first or drop --skip-build)" >&2
      exit 1
    fi
  done
  BIN="$BIN_ARM"
else
  if [ "$SKIP_BUILD" -eq 0 ]; then
    swift build -c "$CONFIG" --product MacContestLogger
  fi
  BIN="$(swift build -c "$CONFIG" --show-bin-path)"
  if [ ! -x "$BIN/MacContestLogger" ]; then
    echo "missing $BIN/MacContestLogger (build it first or drop --skip-build)" >&2
    exit 1
  fi
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
APP="$OUT/MacContestLogger.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" -eq 1 ]; then
  lipo -create "$BIN_ARM/MacContestLogger" "$BIN_X86/MacContestLogger" -output "$APP/Contents/MacOS/MacContestLogger"
  ARCHS="$(lipo -archs "$APP/Contents/MacOS/MacContestLogger")"
  if [ "$ARCHS" != "x86_64 arm64" ]; then
    echo "universal executable has architectures '$ARCHS', expected 'x86_64 arm64'" >&2
    exit 1
  fi
  echo "architectures: $ARCHS"
else
  cp "$BIN/MacContestLogger" "$APP/Contents/MacOS/MacContestLogger"
fi
sed "s/@VERSION@/$VERSION/g" packaging/Info.plist.in > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# The resource bundles of the app's targets, by explicit name: a stale bundle left in a (cached) .build by a removed
# target must not ship, and test-target bundles (fixtures) do not belong in the app. A new target with resources =
# a new name here.
RESOURCE_BUNDLES=(MacContestLogger_MCLCore.bundle)
for name in "${RESOURCE_BUNDLES[@]}"; do
  if [ ! -d "$BIN/$name" ]; then
    echo "missing resource bundle $BIN/$name" >&2
    exit 1
  fi
  if [ "$UNIVERSAL" -eq 1 ]; then
    # Resources do not depend on the architecture; a difference means the two builds saw different sources.
    if ! diff -r "$BIN_ARM/$name" "$BIN_X86/$name"; then
      echo "resource bundle $name differs between $ARM_TRIPLE and $X86_TRIPLE" >&2
      exit 1
    fi
  fi
  cp -R "$BIN/$name" "$APP/Contents/Resources/"
  echo "resource bundle: $name"
done

if [ -z "$SIGN_IDENTITY" ]; then
  codesign --force --deep -s - "$APP"
else
  plutil -lint "$ENTITLEMENTS"
  SIGN_ARGS=(--force --options runtime -s "$SIGN_IDENTITY")
  if [ "$TIMESTAMP" -eq 1 ] && [ "$SIGN_IDENTITY" != "-" ]; then
    SIGN_ARGS+=(--timestamp)
  elif [ "$SIGN_IDENTITY" != "-" ]; then
    echo "warning: signing without --timestamp; the result cannot be notarized" >&2
  fi
  # Inside-out: the deepest nested code first, the app last. Code bundles (with Contents/MacOS or a framework
  # layout) are signed as a whole, loose Mach-O files one by one.
  MAIN_EXE="$APP/Contents/MacOS/MacContestLogger"
  NESTED=()
  while IFS= read -r -d '' f; do
    [ "$f" = "$MAIN_EXE" ] && continue
    if file -b "$f" | grep -q 'Mach-O'; then
      NESTED+=("$f")
    fi
  done < <(find "$APP/Contents" -type f -print0)
  while IFS= read -r -d '' b; do
    if [ -d "$b/Contents/MacOS" ] || [ -d "$b/Versions" ]; then
      NESTED+=("$b")
    fi
  done < <(find "$APP/Contents" -mindepth 1 -type d \( -name '*.framework' -o -name '*.bundle' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) -print0)
  if [ "${#NESTED[@]}" -gt 0 ]; then
    # Deeper paths first (more slashes = deeper).
    while IFS= read -r item; do
      echo "signing nested: ${item#"$APP/"}"
      codesign "${SIGN_ARGS[@]}" "$item"
    done < <(for item in "${NESTED[@]}"; do printf '%s\t%s\n' "$(printf '%s' "$item" | tr -cd '/' | wc -c)" "$item"; done \
      | sort -t $'\t' -k1,1nr | cut -f2-)
  else
    echo "signing nested: none"
  fi
  codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP"
fi
codesign --verify --deep --strict "$APP"
if [ -n "$SIGN_IDENTITY" ]; then
  # Identity, team, flags (runtime), timestamp — no secrets in this output.
  codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Format|CodeDirectory|Signature|Authority|TeamIdentifier|Timestamp|Runtime Version)'
  codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - || true
fi

"$APP/Contents/MacOS/MacContestLogger" --self-check
echo "self-check passed: $APP"

if [ "$DMG" -eq 1 ]; then
  if [ "$UNIVERSAL" -eq 1 ]; then
    DMG_FILE="$OUT/MacContestLogger-$FILE_VERSION-macos-universal.dmg"
  else
    DMG_FILE="$OUT/MacContestLogger-$FILE_VERSION.dmg"
  fi
  STAGE="$OUT/dmg-staging"
  rm -rf "$STAGE" "$DMG_FILE" "$DMG_FILE.sha256"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname MacContestLogger -srcfolder "$STAGE" -format UDZO -ov "$DMG_FILE"
  rm -rf "$STAGE"
  if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    DMG_SIGN_ARGS=(--force -s "$SIGN_IDENTITY")
    if [ "$TIMESTAMP" -eq 1 ]; then
      DMG_SIGN_ARGS+=(--timestamp)
    fi
    codesign "${DMG_SIGN_ARGS[@]}" "$DMG_FILE"
    codesign --verify --strict "$DMG_FILE"
    codesign -dv "$DMG_FILE" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Timestamp)'
  fi
  if [ "$UNIVERSAL" -eq 1 ]; then
    hdiutil verify "$DMG_FILE"
    (cd "$OUT" && shasum -a 256 "$(basename "$DMG_FILE")" > "$(basename "$DMG_FILE").sha256")
    echo "sha256: $DMG_FILE.sha256"
  fi
  echo "dmg: $DMG_FILE"
fi
