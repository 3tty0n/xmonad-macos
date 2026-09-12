#!/bin/bash
source "$(dirname "$0")/common.sh"
need swiftc; need python3
cd "$ROOT"
mkdir -p build/tests
swiftc -swift-version 5 -parse-as-library native/Wire.swift native/Border.swift tests/WireTests.swift -o build/tests/wire-tests
build/tests/wire-tests
swiftc -frontend -parse -swift-version 5 native/*.swift
for script in scripts/*.sh; do bash -n "$script"; done
python3 -m py_compile tests/integration.py
python3 tests/static_checks.py
