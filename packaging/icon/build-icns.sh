#!/usr/bin/env bash
# Builds packaging/AppIcon.icns from the SVG sources in this folder.
#
#   packaging/icon/build-icns.sh
#
# AppIcon.svg is the full icon (frequency display + VFO knob) for 64 px and up; AppIcon-small.svg is the same
# icon without the fine detail (labels, Morse mark, scale ticks) for 16 and 32 px, where the detail turns to noise.
# Both are 1024 x 1024 with the macOS icon grid: the rounded body is 824 px with a 100 px margin for the shadow.
# The "VFO A" label uses Menlo, which every Mac has.
# Needs rsvg-convert (brew install librsvg) and iconutil (Xcode command line tools).
set -euo pipefail
cd "$(dirname "$0")"
command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
set_dir="$tmp/AppIcon.iconset"; mkdir "$set_dir"
render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$set_dir/$3"; }
render AppIcon-small.svg 16 icon_16x16.png
render AppIcon-small.svg 32 icon_16x16@2x.png
render AppIcon-small.svg 32 icon_32x32.png
render AppIcon.svg       64 icon_32x32@2x.png
render AppIcon.svg      128 icon_128x128.png
render AppIcon.svg      256 icon_128x128@2x.png
render AppIcon.svg      256 icon_256x256.png
render AppIcon.svg      512 icon_256x256@2x.png
render AppIcon.svg      512 icon_512x512.png
render AppIcon.svg     1024 icon_512x512@2x.png
iconutil -c icns "$set_dir" -o ../AppIcon.icns
rsvg-convert -w 1024 -h 1024 AppIcon.svg -o AppIcon-1024.png
echo "packaging/AppIcon.icns, packaging/icon/AppIcon-1024.png"
