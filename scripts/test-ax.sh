#!/bin/bash
# Build the fixture and run the desktop AX checks against the running helper.
# Requires Accessibility permission for XMonadMac and a logged-in desktop.
source "$(dirname "$0")/common.sh"
mac_only; need python3
"$ROOT/scripts/build-ax-fixture.sh"
exec python3 "$ROOT/tests/ax_harness.py" "$@"
