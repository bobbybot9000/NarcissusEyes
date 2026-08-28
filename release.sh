#!/bin/bash
# Builds the Mac App Store submission package.
#
#   ./release.sh
#
# Produces build/export/Narcissus.pkg, signed with Apple Distribution and the
# 3rd Party Mac Developer Installer cert. Upload it with Xcode's Organizer or
# Apple's Transporter app — both handle the Apple ID sign-in that this script
# deliberately does not touch.
#
# Bump CURRENT_PROJECT_VERSION in the Xcode project before each upload; App
# Store Connect rejects a build number it has already seen.

set -euo pipefail
cd "$(dirname "$0")"

ARCHIVE="build/Narcissus.xcarchive"
EXPORT="build/export"

rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p build

echo "==> Archiving"
xcodebuild -project Narcissus.xcodeproj \
    -scheme Narcissus \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    archive

echo "==> Exporting for App Store"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath "$EXPORT" \
    -allowProvisioningUpdates

echo ""
echo "==> Package ready: $EXPORT/Narcissus.pkg"
pkgutil --check-signature "$EXPORT/Narcissus.pkg" | head -4
