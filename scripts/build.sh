#!/bin/bash
source "$(dirname "$0")/common.sh"
"$ROOT/scripts/build-native.sh"
"$ROOT/scripts/build-engine.sh" "$@"
