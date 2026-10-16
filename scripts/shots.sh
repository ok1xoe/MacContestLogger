#!/usr/bin/env bash
# Renders the user guide's screenshots offscreen (no screen, screen saver or unlocked session needed; the app is not
# started): the windows listed as rendered in docs/screenshots.json, over a demo model with inert hardware and network,
# in one UI language. See docs/screenshots.md.
#
#   scripts/shots.sh --lang cs|en [--only name[,name...]] [--out dir]
#
# Default output: build/shots/<lang>/<name>.png. To update the guide, copy the Czech images to docs/img/ and the
# English ones to docs/img/en/ (only when the owner asks for it).
set -euo pipefail
cd "$(dirname "$0")/.."
LANG_CODE=""
ONLY=""
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lang) LANG_CODE="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "shots.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$LANG_CODE" in
  cs|en) ;;
  *) echo "shots.sh: --lang cs or --lang en is required" >&2; exit 2 ;;
esac
OUT="${OUT:-build/shots/$LANG_CODE}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
export MCL_SHOTS_DIR="$OUT" MCL_SHOTS_LANG="$LANG_CODE" MCL_SHOTS_ONLY="$ONLY"
export MCL_INERT_HARDWARE=1 MCL_INERT_NETWORK=1
LOG="$(mktemp -t mcl-shots)"
trap 'rm -f "$LOG"' EXIT
set +e
scripts/test.sh --filter 'ScreenshotTests' >"$LOG" 2>&1
STATUS=$?
set -e
grep -E '^shots:|✘|error:|recorded an issue' "$LOG" || true
if [ "$STATUS" -ne 0 ]; then
  tail -40 "$LOG" >&2
  echo "shots.sh: the render failed" >&2
  exit "$STATUS"
fi
echo "shots.sh: images in $OUT"
