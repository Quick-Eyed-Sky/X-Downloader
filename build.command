#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build in a temporary folder: a failed compile must not leave a broken app.
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/x-downloader.XXXXXX")
cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT
trap 'echo "Build failed. The previous application has been kept." >&2' ERR
APP="$BUILD_DIR/X Downloader.app"
OUTPUT="$PWD/dist/X Downloader.app"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Install Apple's Command Line Tools first: xcode-select --install"
    exit 1
fi
ARCH=$(uname -m)
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH"; exit 1 ;; esac
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>XDownloader</string>
<key>CFBundleIdentifier</key><string>io.github.quick-eyed-sky.xdownloader</string>
<key>CFBundleName</key><string>X Downloader</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>3.2.1</string>
<key>CFBundleVersion</key><string>321</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "Building X Downloader for ${ARCH}..."
xcrun swiftc XDownloader.swift -o "$APP/Contents/MacOS/XDownloader" \
    -target "$ARCH-apple-macosx13.0" -swift-version 5 \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    -framework SwiftUI -framework CryptoKit -parse-as-library

cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

test -x "$APP/Contents/MacOS/XDownloader"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
mkdir -p dist
if [ -e "$OUTPUT" ]; then
    BACKUP="$PWD/dist/X Downloader.previous.$(date +%Y%m%d-%H%M%S).$$.app"
    mv "$OUTPUT" "$BACKUP"
    echo "Previous build preserved: $BACKUP"
fi
mv "$APP" "$OUTPUT"
echo "Created: $OUTPUT"
echo "Open this application in Finder. You can copy it into Applications."
