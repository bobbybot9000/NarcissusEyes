#!/bin/bash
# Builds build/LookNice.dmg — the drag-to-Applications disk image for direct
# download from a website.
#
#   ./make_dmg.sh
#
# NOTE ON GATEKEEPER: this image is code-signed but NOT notarized, so on a
# machine other than this one macOS will refuse to open it on a double-click
# ("Apple could not verify this app is free from malware"). Recipients have to
# right-click the app and choose Open, once. Notarizing removes that; it needs
# a Developer ID certificate and an app-specific password.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LookNice"
VOL_NAME="LookNice"
STAGE="build/dmg-stage"
RW_DMG="build/rw.dmg"
OUT_DMG="build/${APP_NAME}.dmg"

echo "==> Building the app"
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination 'platform=macOS' \
    -allowProvisioningUpdates \
    build > /dev/null

BUILT=$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | grep -m1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //')
APP="${BUILT}/${APP_NAME}.app"
[ -d "$APP" ] || { echo "No app at $APP"; exit 1; }

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

# Finder has to be scripted to place the icons and apply the background.
# If automation permission is refused the image still works — it just opens
# as a plain list of two items — so a failure here is a warning, not fatal.
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
  echo "    The image still installs correctly, it just won't be styled."
fi

sync
hdiutil detach "$MOUNT" > /dev/null

echo "==> Compressing"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" > /dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE"

echo ""
echo "==> $OUT_DMG"
ls -lh "$OUT_DMG" | awk '{print "    " $5}'
