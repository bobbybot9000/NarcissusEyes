#!/bin/bash
# Builds a throwaway copy of the app whose mirror CAN be screenshotted, for
# App Store screenshots. The shipped app excludes itself from screen capture,
# so the real thing cannot be photographed for its own listing.
#
#   Tools/screenshot_build.sh && open build/LookNice-Screenshots.app
#
# Then cmd-shift-3. Mac App Store sizes are 16:10: 2880x1800, 2560x1600,
# 1440x900 or 1280x800 — crop or resize to one of those. Never upload or
# distribute this build.

set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release -Xswiftc -DSCREENSHOTS

APP="build/LookNice-Screenshots.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release -Xswiftc -DSCREENSHOTS --show-bin-path)/LookNice" "$APP/Contents/MacOS/LookNice"
cp Sources/LookNice/Info.plist "$APP/Contents/Info.plist"
# Its own identity, so it does not share camera permission or saved state
# with the real app.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.bobbystrobeck.looknice.screenshots" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
