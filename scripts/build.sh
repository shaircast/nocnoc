#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
APP_NAME="nocnoc"
BUNDLE_ID="com.saturnstudio.nocnoc"
VERSION="1.0.1"
BUILD_NUMBER="2"
ENTITLEMENTS="entitlements.plist"
IDENTITY="${APPLE_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"

DIST_DIR="dist"
BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP="$DIST_DIR/$APP_NAME.zip"
DMG="$DIST_DIR/$APP_NAME.dmg"
SIGNED_RELEASE=false

if [ -n "$IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    SIGNED_RELEASE=true
fi

# ── Step 1: Build ──────────────────────────────────────────────
echo "▸ Building with Swift (release)..."
swift build -c release --arch arm64
echo "  ✓ Build complete"

# ── Step 2: Create .app bundle ─────────────────────────────────
echo "▸ Creating .app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# Copy binary
cp .build/arm64-apple-macosx/release/nocnoc "$BUNDLE/Contents/MacOS/$APP_NAME"

# Copy icon if it exists
if [ -f "assets/$APP_NAME.icns" ]; then
    cp "assets/$APP_NAME.icns" "$BUNDLE/Contents/Resources/"
    ICON_FILE="$APP_NAME.icns"
else
    ICON_FILE=""
    echo "  ⚠ No icon found at assets/$APP_NAME.icns — bundle will use default icon"
fi

# Generate Info.plist
cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_FILE</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>nocnoc needs to send Apple Events to execute actions like toggling mute and locking the screen.</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST
echo "  ✓ .app bundle created"

if [ "$SIGNED_RELEASE" != true ]; then
    echo ""
    echo "⚠ Skipping signing and notarization."
    echo "  To produce a signed release, set both APPLE_CODESIGN_IDENTITY and APPLE_NOTARY_PROFILE."
    echo "  Unsigned app ready: $BUNDLE"
    exit 0
fi

# ── Step 3: Sign ───────────────────────────────────────────────
echo "▸ Signing application..."

# Sign embedded dylibs/frameworks if any
find "$BUNDLE" -type f \( -name "*.dylib" -o -name "*.so" \) | while read -r lib; do
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$IDENTITY" \
        --timestamp \
        "$lib"
done

# Sign the main executable
codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    --timestamp \
    "$BUNDLE/Contents/MacOS/$APP_NAME"

# Sign the .app bundle
codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    --timestamp \
    "$BUNDLE"

echo "  ✓ Signing complete"

# ── Step 4: Verify signature ──────────────────────────────────
echo "▸ Verifying signature..."
codesign --verify --deep --strict "$BUNDLE"
echo "  ✓ Signature valid"

# ── Step 5: Notarize ──────────────────────────────────────────
echo "▸ Creating zip for notarization..."
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

echo "▸ Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# ── Step 6: Staple ────────────────────────────────────────────
echo "▸ Stapling notarization ticket..."
xcrun stapler staple "$BUNDLE"
echo "  ✓ Staple complete"

# ── Step 7: Final verification ────────────────────────────────
echo "▸ Final Gatekeeper check..."
spctl --assess --type exec --verbose "$BUNDLE"

# ── Step 8: Create distribution DMG ──────────────────────────
echo "▸ Creating DMG..."
rm -f "$DMG"
DMG_STAGE=$(mktemp -d)
cp -R "$BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" \
    -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGE"

echo "▸ Signing DMG..."
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "▸ Notarizing DMG..."
xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "▸ Stapling DMG..."
xcrun stapler staple "$DMG"
echo "  ✓ DMG ready: $DMG"

echo ""
echo "✓ Done! $DMG is signed, notarized, and ready for distribution."
