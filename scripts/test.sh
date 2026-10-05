#!/usr/bin/env bash
# Runs the tests. Command Line Tools do not load the swift-testing macro plugin on their own;
# with full Xcode the flag is unnecessary but harmless.
set -euo pipefail
PLUGIN=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
ARGS=()
if [ -f "$PLUGIN" ]; then
  ARGS=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
fi
exec swift test "${ARGS[@]}" "$@"
