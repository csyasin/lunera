#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
xcodebuild -project "$PROJECT_DIR/Lunera.xcodeproj" -scheme Lunera -configuration Release -derivedDataPath "$PROJECT_DIR/build" build
printf '\nLunera.app: %s\n' "$PROJECT_DIR/build/Build/Products/Release/Lunera.app"
