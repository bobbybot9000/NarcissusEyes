#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary (Apple Silicon + Intel). Build each slice with --triple and
# lipo them together — `swift build --arch a --arch b` needs full Xcode's
# XCBuild, but per-triple builds work with Command Line Tools alone.
swift build -c release --triple arm64-apple-macosx12.0
swift build -c release --triple x86_64-apple-macosx12.0

APP="LookNice.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

lipo -create \
    .build/arm64-apple-macosx/release/LookNice \
    .build/x86_64-apple-macosx/release/LookNice \
    -output "$APP/Contents/MacOS/LookNice"
cp Sources/LookNice/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so macOS grants camera permission prompts correctly.
# (App Store distribution uses the Xcode archive path instead of this script.)
codesign --force --deep --sign - "$APP"

lipo -info "$APP/Contents/MacOS/LookNice"
echo "Built $APP"
