#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lunera-calendar-check.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$TEST_DIR/module-cache" -o "$TEST_DIR/check" "$PROJECT_DIR/Sources/Lunera/Calendar/CalendarStore.swift" "$PROJECT_DIR/Tests/CalendarCheck.swift"
TZ=Asia/Shanghai "$TEST_DIR/check"
