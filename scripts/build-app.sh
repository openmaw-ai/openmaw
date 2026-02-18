#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="OpenTolk"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
BUILD_DIR="$PROJECT_DIR/.build"

echo "Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c debug

# --dev: run binary directly (uses Terminal's accessibility permissions)
if [[ "${1:-}" == "--dev" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    echo "Running in dev mode (binary)..."
    exec "$BUILD_DIR/debug/$APP_NAME"
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy binary
cp "$BUILD_DIR/debug/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy resources
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/"
cp "$PROJECT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/" 2>/dev/null || true

# Embed provisioning profile (required for Sign in with Apple)
PROVISION_PROFILE="$PROJECT_DIR/Resources/OpenTolk_Dev.provisionprofile"
if [ -f "$PROVISION_PROFILE" ]; then
    cp "$PROVISION_PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"
fi

# Embed Sparkle framework
SPARKLE="$BUILD_DIR/debug/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    cp -R "$SPARKLE" "$APP_DIR/Contents/Frameworks/"
fi

# Set rpath so the binary can find Sparkle in Frameworks/
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Sign with developer certificate (matching Xcode's signing approach)
SIGNING_HASH=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -z "$SIGNING_HASH" ]; then
    echo "Warning: No Apple Development certificate found, using ad-hoc signing"
    SIGNING_HASH="-"
fi

# Sign embedded frameworks first
if [ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --sign "$SIGNING_HASH" --timestamp=none --generate-entitlement-der \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null || true
    codesign --force --sign "$SIGNING_HASH" --timestamp=none --generate-entitlement-der \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null || true
    codesign --force --sign "$SIGNING_HASH" --timestamp=none --generate-entitlement-der \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null || true
    codesign --force --sign "$SIGNING_HASH" --timestamp=none --generate-entitlement-der \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
fi

# Sign main app (same flags as Xcode: --generate-entitlement-der for AMFI validation)
codesign --force --sign "$SIGNING_HASH" \
    --entitlements "$PROJECT_DIR/Resources/OpenTolk.entitlements" \
    --timestamp=none \
    --generate-entitlement-der \
    "$APP_DIR"

echo "Built: $APP_DIR"

# Launch if --run flag is passed
if [[ "${1:-}" == "--run" ]]; then
    echo "Launching $APP_NAME..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    open "$APP_DIR"
fi
