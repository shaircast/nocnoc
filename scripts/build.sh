#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# ── Configuration ──────────────────────────────────────────────
APP_NAME="nocnoc"
BUNDLE_ID="com.saturnstudio.nocnoc"
VERSION="1.0.3"
BUILD_NUMBER="4"
ENTITLEMENTS="entitlements.plist"
IDENTITY="${APPLE_CODESIGN_IDENTITY:-Developer ID Application: Saturn Studio (449B2G47F7)}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-notarytool-profile}"
SPARKLE_ROOT=".build/artifacts/sparkle/Sparkle"
SPARKLE_FEED_URL="https://github.com/shaircast/nocnoc/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY_FILE="sparkle-public-key.txt"

DIST_DIR="dist"
BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP="$DIST_DIR/$APP_NAME.zip"
DMG="$DIST_DIR/$APP_NAME.dmg"
SIGNED_RELEASE=true

case "${1:-}" in
    --unsigned) SIGNED_RELEASE=false ;;
    --help|-h)
        echo "Usage: $0 [--unsigned]"
        echo "  Default: build, sign, notarize, and prepare ZIP, DMG, and appcast.xml."
        echo "  --unsigned: build a locally ad-hoc signed .app without Developer ID or notarization."
        exit 0
        ;;
    "") ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
esac
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [--unsigned]" >&2
    exit 1
fi

if [ ! -f "$SPARKLE_PUBLIC_KEY_FILE" ]; then
    echo "Missing $SPARKLE_PUBLIC_KEY_FILE. See the Sparkle release setup in README.md." >&2
    exit 1
fi
SPARKLE_PUBLIC_KEY=$(tr -d '[:space:]' < "$SPARKLE_PUBLIC_KEY_FILE")
if [[ ! "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Invalid Ed25519 public key in $SPARKLE_PUBLIC_KEY_FILE." >&2
    exit 1
fi

# ── Step 1: Build ──────────────────────────────────────────────
echo "▸ Building with Swift (release)..."
swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Sparkle framework not found at $SPARKLE_FRAMEWORK." >&2
    exit 1
fi
if [ "$SIGNED_RELEASE" = true ]; then
    SIGNING_PUBLIC_KEY=$("$SPARKLE_ROOT/bin/generate_keys" \
        --account com.saturnstudio.nocnoc.sparkle -p)
    if [ "$SPARKLE_PUBLIC_KEY" != "$SIGNING_PUBLIC_KEY" ]; then
        echo "The Sparkle Keychain key does not match $SPARKLE_PUBLIC_KEY_FILE." >&2
        echo "Restore the release key to account com.saturnstudio.nocnoc.sparkle before signing." >&2
        exit 1
    fi
fi
echo "  ✓ Build complete"

# ── Step 2: Create .app bundle ─────────────────────────────────
echo "▸ Creating .app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
mkdir -p "$BUNDLE/Contents/Frameworks"

# Copy binary
cp "$BIN_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Sparkle includes versioned symlinks and nested helper executables; preserve both.
EMBEDDED_SPARKLE="$BUNDLE/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$EMBEDDED_SPARKLE"
cp "$SPARKLE_ROOT/LICENSE" "$BUNDLE/Contents/Resources/Sparkle-LICENSE"

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
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
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
    <key>SUFeedURL</key>
    <string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>14400</integer>
</dict>
</plist>
PLIST
plutil -lint "$BUNDLE/Contents/Info.plist"
echo "  ✓ .app bundle created"

if [ "$SIGNED_RELEASE" != true ]; then
    # Seal the generated Info.plist/resources for local use without a Keychain
    # identity. Keep Sparkle's original nested signatures intact.
    codesign --force --sign - --timestamp=none \
        --entitlements "$ENTITLEMENTS" "$BUNDLE"
    codesign --verify --deep --strict "$BUNDLE"
    echo ""
    echo "Skipping Developer ID signing, notarization, archives, and appcast generation."
    echo "  Locally ad-hoc signed app ready: $BUNDLE (no Keychain access)"
    exit 0
fi

# ── Step 3: Sign ───────────────────────────────────────────────
echo "▸ Signing application..."

# Sign nested Sparkle code before the framework and enclosing app. Downloader's
# sandbox entitlements must survive; the app's entitlements do not belong here.
SPARKLE_VERSION="$EMBEDDED_SPARKLE/Versions/Current"
codesign --force --options runtime --sign "$IDENTITY" --timestamp \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign --force --options runtime --preserve-metadata=entitlements \
    --sign "$IDENTITY" --timestamp \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "$IDENTITY" --timestamp \
    "$SPARKLE_VERSION/Autoupdate"
codesign --force --options runtime --sign "$IDENTITY" --timestamp \
    "$SPARKLE_VERSION/Updater.app"
codesign --force --options runtime --sign "$IDENTITY" --timestamp \
    "$EMBEDDED_SPARKLE"

# Sign the app and its main executable together.
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
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

echo "▸ Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# ── Step 6: Staple ────────────────────────────────────────────
echo "▸ Stapling notarization ticket..."
xcrun stapler staple "$BUNDLE"
xcrun stapler validate "$BUNDLE"
echo "  ✓ Staple complete"

# The published archive must contain the stapled app, not the pre-notary copy.
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

# ── Step 7: Final verification ────────────────────────────────
echo "▸ Final Gatekeeper check..."
spctl --assess --type exec --verbose "$BUNDLE"

# ── Step 8: Create distribution DMG ──────────────────────────
echo "▸ Creating DMG..."
rm -f "$DMG"
DMG_STAGE=$(mktemp -d)
trap 'rm -rf "$DMG_STAGE"' EXIT
ditto "$BUNDLE" "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" \
    -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGE"
trap - EXIT

echo "▸ Signing DMG..."
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "▸ Notarizing DMG..."
xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "▸ Stapling DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "  ✓ DMG ready: $DMG"

echo "▸ Generating signed Sparkle appcast from the final ZIP..."
./scripts/generate-appcast.sh "$ZIP"

echo ""
echo "✓ Release files ready: $ZIP, $DMG, $DIST_DIR/appcast.xml"
echo "  Upload all three to the GitHub release tagged v$VERSION."
echo "  No release has been published."
