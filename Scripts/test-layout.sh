#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lunera-layout-check.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$TEST_DIR/module-cache" -o "$TEST_DIR/check" "$PROJECT_DIR/Sources/Lunera/UI/CalendarPanelLayout.swift" "$PROJECT_DIR/Tests/LayoutCheck.swift"
"$TEST_DIR/check"
