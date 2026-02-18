#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building OpenTolk..."
swift build -c release

echo "Creating .app bundle..."
rm -rf OpenTolk.app
mkdir -p OpenTolk.app/Contents/MacOS
mkdir -p OpenTolk.app/Contents/Resources
mkdir -p OpenTolk.app/Contents/Frameworks

cp .build/release/OpenTolk OpenTolk.app/Contents/MacOS/
cp Resources/Info.plist OpenTolk.app/Contents/
cp Resources/OpenTolk.entitlements OpenTolk.app/Contents/Resources/
cp Resources/PrivacyInfo.xcprivacy OpenTolk.app/Contents/Resources/ 2>/dev/null || true

# Bundle Sparkle.framework
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [ -n "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" OpenTolk.app/Contents/Frameworks/
    install_name_tool -add_rpath "@executable_path/../Frameworks" OpenTolk.app/Contents/MacOS/OpenTolk 2>/dev/null || true
fi

# Sign with developer certificate (required for Sign in with Apple)
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="-"
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --entitlements Resources/OpenTolk.entitlements \
    OpenTolk.app

echo ""
echo "Build complete! Run with:"
echo "  open OpenTolk.app"
echo ""
echo "Note: Your Groq API key is loaded from Keychain (set in Settings/Onboarding)"
echo "      or from the GROQ_API_KEY environment variable."
