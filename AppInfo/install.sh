#!/bin/bash
set -e

# ==============================================================================
# Appinfo Installer Script
# Builds and installs Appinfo to /usr/local/bin for system-wide Terminal access.
# ==============================================================================

TOOL_NAME="appinfo"
ALIAS_NAME="appinspect"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
INSTALL_DIR="/usr/local/bin"

echo "=========================================================="
echo " 📦 Installing Appinfo (App & Sparkle Inspector)"
echo "=========================================================="

# Check for Xcode command line tools / xcodebuild
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌ Error: xcodebuild is required but not found."
    exit 1
fi

echo "🔨 Building Release binary with xcodebuild..."
xcodebuild -project "${PROJECT_DIR}/Untitled Project.xcodeproj" \
           -scheme "MyTool" \
           -configuration Release \
           -derivedDataPath "${BUILD_DIR}" \
           build > /dev/null

BINARY_PATH=$(find "${BUILD_DIR}/Build/Products/Release" -name "Appinfo" -type f -perm +111 2>/dev/null | head -n 1)

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
    # Fallback search in Products
    BINARY_PATH=$(find "${BUILD_DIR}" -name "Appinfo" -type f -perm +111 2>/dev/null | head -n 1)
fi

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: Could not locate built binary."
    exit 1
fi

echo "✅ Built successfully at: ${BINARY_PATH}"

# Ensure /usr/local/bin exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating ${INSTALL_DIR}..."
    sudo mkdir -p "$INSTALL_DIR"
fi

echo "🚀 Installing to ${INSTALL_DIR}/${TOOL_NAME}..."
sudo cp -f "${BINARY_PATH}" "${INSTALL_DIR}/${TOOL_NAME}"
sudo chmod 755 "${INSTALL_DIR}/${TOOL_NAME}"

echo "🔗 Creating compatibility alias: ${INSTALL_DIR}/${ALIAS_NAME} -> ${INSTALL_DIR}/${TOOL_NAME}..."
sudo ln -sf "${INSTALL_DIR}/${TOOL_NAME}" "${INSTALL_DIR}/${ALIAS_NAME}"

# Clean up temporary build artifacts
rm -rf "${BUILD_DIR}"

echo ""
echo "=========================================================="
echo "🎉 Installation Complete!"
echo "=========================================================="
echo "You can now run either command in Terminal:"
echo "   ${TOOL_NAME}"
echo "   ${ALIAS_NAME}"
echo ""
echo "Try running:"
echo "   ${TOOL_NAME} /Applications/Safari.app"
echo "or just:"
echo "   ${TOOL_NAME}"
echo "and drag & drop an app onto the terminal window!"
echo "=========================================================="
