#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "$#" -gt 1 ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 [dist/nocnoc.zip]"
    echo "Generate dist/appcast.xml from a signed, notarized, stapled release ZIP."
    if [ "$#" -gt 1 ]; then exit 1; fi
    exit 0
fi

ARCHIVE="${1:-dist/nocnoc.zip}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
SPARKLE_ACCOUNT="com.saturnstudio.nocnoc.sparkle"
RELEASE_BASE_URL="https://github.com/shaircast/nocnoc/releases"
APPCAST="dist/appcast.xml"

if [ ! -f "$ARCHIVE" ] || [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "Missing release ZIP or Sparkle tools. Run ./scripts/build.sh first." >&2
    exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/archives" "$STAGE/extracted"
cp "$ARCHIVE" "$STAGE/archives/nocnoc.zip"
ditto -x -k "$STAGE/archives/nocnoc.zip" "$STAGE/extracted"
APP="$STAGE/extracted/nocnoc.app"
PLIST="$APP/Contents/Info.plist"

# Read metadata from the exact bytes that will be downloaded, not another build.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a release version such as 1.0.3; found $VERSION." >&2
    exit 1
fi
COMMITTED_PUBLIC_KEY=$(tr -d '[:space:]' < sparkle-public-key.txt)
if [ "$PUBLIC_KEY" != "$COMMITTED_PUBLIC_KEY" ]; then
    echo "The release's Sparkle public key does not match sparkle-public-key.txt." >&2
    exit 1
fi
SIGNING_PUBLIC_KEY=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
if [ "$PUBLIC_KEY" != "$SIGNING_PUBLIC_KEY" ]; then
    echo "The release's Sparkle public key does not match Keychain account $SPARKLE_ACCOUNT." >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"

# Isolate this ZIP from the DMG and older builds. Each release's enclosure uses
# its immutable tag URL, while the app reads appcast.xml via /releases/latest/.
"$SPARKLE_BIN/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$RELEASE_BASE_URL/download/v$VERSION/" \
    --link "$RELEASE_BASE_URL/tag/v$VERSION" \
    --maximum-deltas 0 \
    -o "$STAGE/appcast.xml" \
    "$STAGE/archives"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$STAGE/appcast.xml"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$STAGE/appcast.xml"
mkdir -p dist
cp "$STAGE/appcast.xml" "$APPCAST"

echo "✓ $APPCAST is ready for v$VERSION (upload the archive as nocnoc.zip)."
