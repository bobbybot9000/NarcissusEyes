#!/bin/bash
# Builds build/LookNice.dmg — the drag-to-Applications disk image for direct
# download from a website.
#
#   ./make_dmg.sh
#
# Signs with Developer ID, then notarizes with Apple and staples the ticket, so
# the app opens on a first double-click with no "unverified developer" wall.
#
# ONE-TIME SETUP for notarization (needs an app-specific password from
# appleid.apple.com — Sign-In and Security > App-Specific Passwords):
#
#   xcrun notarytool store-credentials "looknice-notary" \
#       --apple-id "bobbystrobeck@gmail.com" --team-id YTLXVW7AA5
#
# It prompts for the password and saves it to your keychain; this script never
# sees it. Without that profile the script still builds a signed DMG, it just
# skips notarization and says so.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LookNice"
VOL_NAME="LookNice"
TEAM_ID="YTLXVW7AA5"
NOTARY_PROFILE="looknice-notary"

ARCHIVE="build/${APP_NAME}.xcarchive"
EXPORT="build/export-developer-id"
APP="${EXPORT}/${APP_NAME}.app"
STAGE="build/dmg-stage"
RW_DMG="build/rw.dmg"
OUT_DMG="build/${APP_NAME}.dmg"

mkdir -p build

echo "==> Archiving"
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    archive > /dev/null

echo "==> Exporting, signed with Developer ID"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist ExportOptions-DeveloperID.plist \
    -exportPath "$EXPORT" \
    -allowProvisioningUpdates > /dev/null
[ -d "$APP" ] || { echo "No app at $APP"; exit 1; }

codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^Authority=Developer ID" \
    || { echo "Not signed with Developer ID — cannot notarize."; exit 1; }

# ---- Notarize the app itself -------------------------------------------------
# Stapling the ticket to the .app (rather than only to the .dmg) means the app
# stays verified even after someone drags it out of the image.
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing (a few minutes; Apple's queue decides)"
    ZIP="build/${APP_NAME}-notarize.zip"
    rm -f "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

    if xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
        xcrun stapler staple "$APP"
        echo "    ticket stapled to the app"
        NOTARIZED=1
    else
        echo "    NOTARIZATION FAILED — see the log above."
        echo "    Run: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
        NOTARIZED=0
    fi
    rm -f "$ZIP"
else
    echo "==> Skipping notarization: no keychain profile '$NOTARY_PROFILE'."
    echo "    Set it up once with:"
    echo "      xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "          --apple-id \"bobbystrobeck@gmail.com\" --team-id $TEAM_ID"
    echo "    Until then the app is signed but users will hit Gatekeeper."
    NOTARIZED=0
fi

# ---- Build the disk image ----------------------------------------------------
echo "==> Drawing the window background"
swift Tools/make_dmg_bg.swift > /dev/null

echo "==> Staging"
rm -rf "$STAGE" "$RW_DMG" "$OUT_DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp build/dmg-bg.png "$STAGE/.background/bg.png"

echo "==> Creating a writable image"
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -ov "$RW_DMG" > /dev/null

MOUNT="/Volumes/${VOL_NAME}"
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT" -nobrowse > /dev/null

# Finder places the icons and applies the background. If automation permission
# is refused the image still installs fine, it just isn't styled.
echo "==> Arranging the window"
if osascript <<EOF >/dev/null 2>&1
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 12
    set background picture of opts to file ".background:bg.png"
    set position of item "${APP_NAME}.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF
then
  echo "    window arranged"
else
  echo "    WARNING: could not script Finder (automation permission?)."
fi

sync
hdiutil detach "$MOUNT" > /dev/null

echo "==> Compressing"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" > /dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE"

# Notarizing the image as well covers the download itself, not just the app
# inside it, so mounting a freshly downloaded DMG is silent too.
if [ "$NOTARIZED" = "1" ]; then
    echo "==> Notarizing the disk image"
    if xcrun notarytool submit "$OUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait; then
        xcrun stapler staple "$OUT_DMG"
        echo "    ticket stapled to the image"
    else
        echo "    Image notarization failed; the app inside is still stapled."
    fi
fi

echo ""
echo "==> $OUT_DMG"
ls -lh "$OUT_DMG" | awk '{print "    " $5}'
echo "==> Gatekeeper verdict:"
spctl -a -vvv -t install "$OUT_DMG" 2>&1 | sed 's/^/    /' || true
