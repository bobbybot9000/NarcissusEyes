#!/bin/bash
# Builds the Mac App Store submission package.
#
#   ./release.sh
#
# Archives into ~/Library/Developer/Xcode/Archives/ so the build shows up in
# Xcode's Organizer (Window > Organizer), and also exports a signed .pkg to
# build/export/ for uploading via Apple's Transporter app.
#
# Upload with Organizer's "Distribute App" or Transporter — both handle the
# Apple ID sign-in that this script deliberately does not touch.
#
# Bump CURRENT_PROJECT_VERSION in the Xcode project before each upload; App
# Store Connect rejects a build number it has already seen.

set -euo pipefail
cd "$(dirname "$0")"

# Xcode's Organizer only indexes archives in this directory, and expects its
# date-stamped naming convention.
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE="$ARCHIVE_DIR/LookNice $(date +'%Y-%m-%d %H.%M').xcarchive"
EXPORT="build/export"

mkdir -p "$ARCHIVE_DIR"
rm -rf "$EXPORT"
mkdir -p build

echo "==> Archiving"
xcodebuild -project LookNice.xcodeproj \
    -scheme LookNice \
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
echo "==> Archive (visible in Xcode Organizer):"
echo "    $ARCHIVE"
echo "==> Package (for Transporter):"
echo "    $EXPORT/LookNice.pkg"
pkgutil --check-signature "$EXPORT/LookNice.pkg" | head -4
