#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="Narcissus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/Narcissus "$APP/Contents/MacOS/Narcissus"
cp Sources/Narcissus/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so macOS grants camera permission prompts correctly.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
