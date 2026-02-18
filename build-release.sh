#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Configuration
APP_NAME="OpenTolk"
BUNDLE_ID="com.opentolk.app"
VERSION=$(cat VERSION | tr -d '[:space:]')
DEVELOPER_ID="${DEVELOPER_ID_APPLICATION:-}" # "Developer ID Application: Your Name (TEAMID)"
APPLE_ID="${NOTARIZE_APPLE_ID:-}"
TEAM_ID="${NOTARIZE_TEAM_ID:-}"
APP_PASSWORD="${NOTARIZE_APP_PASSWORD:-}" # App-specific password

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Step 1: Build universal binary
echo "[1/7] Building universal binary..."
swift build -c release --arch arm64 --arch x86_64

BINARY=".build/apple/Products/Release/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
    # Fallback for non-universal build
    swift build -c release
    BINARY=".build/release/${APP_NAME}"
fi

# Step 2: Create .app bundle
echo "[2/7] Creating .app bundle..."
APP_DIR="${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "$BINARY" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/"
cp Resources/OpenTolk.entitlements "${APP_DIR}/Contents/Resources/"
cp Resources/PrivacyInfo.xcprivacy "${APP_DIR}/Contents/Resources/" 2>/dev/null || true

# Copy Sparkle.framework into the app bundle
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    echo "  Bundling Sparkle.framework..."
    mkdir -p "${APP_DIR}/Contents/Frameworks"
    cp -R "$SPARKLE_FRAMEWORK" "${APP_DIR}/Contents/Frameworks/"
    # Fix rpath
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
fi

# Update version in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_DIR}/Contents/Info.plist"

# Step 3: Codesign
echo "[3/7] Code signing..."
if [ -n "$DEVELOPER_ID" ]; then
    # Sign Sparkle framework first
    if [ -d "${APP_DIR}/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force --options runtime \
            --sign "$DEVELOPER_ID" \
            --timestamp \
            "${APP_DIR}/Contents/Frameworks/Sparkle.framework"
    fi

    codesign --force --options runtime \
        --entitlements Resources/OpenTolk.entitlements \
        --sign "$DEVELOPER_ID" \
        --timestamp \
        "${APP_DIR}"
    echo "  Signed with: ${DEVELOPER_ID}"
else
    codesign --force --sign - "${APP_DIR}"
    echo "  Ad-hoc signed (no Developer ID configured)"
    echo "  Set DEVELOPER_ID_APPLICATION env var for production signing"
fi

# Step 4: Create DMG
echo "[4/7] Creating DMG..."
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="dmg_temp"
rm -rf "$DMG_TEMP" "$DMG_NAME"
mkdir -p "$DMG_TEMP"
cp -R "${APP_DIR}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_NAME}"
rm -rf "$DMG_TEMP"

# Step 5: Sign DMG
if [ -n "$DEVELOPER_ID" ]; then
    echo "[5/7] Signing DMG..."
    codesign --force --sign "$DEVELOPER_ID" --timestamp "${DMG_NAME}"
else
    echo "[5/7] Skipping DMG signing (no Developer ID)"
fi

# Step 6: Notarize
if [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ] && [ -n "$APP_PASSWORD" ]; then
    echo "[6/7] Notarizing..."
    xcrun notarytool submit "${DMG_NAME}" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    echo "[7/7] Stapling..."
    xcrun stapler staple "${DMG_NAME}"
else
    echo "[6/7] Skipping notarization (credentials not configured)"
    echo "  Set NOTARIZE_APPLE_ID, NOTARIZE_TEAM_ID, NOTARIZE_APP_PASSWORD"
    echo "[7/7] Skipping stapling"
fi

echo ""
echo "=== Build Complete ==="
echo "  App: ${APP_DIR}"
echo "  DMG: ${DMG_NAME}"
echo "  Version: ${VERSION}"
