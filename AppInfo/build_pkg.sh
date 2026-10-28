#!/bin/bash
set -e

# ==============================================================================
# Script to build a standalone macOS Installer Package (.pkg) for Appinfo
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
PKG_ROOT="${PROJECT_DIR}/pkg_root"
OUTPUT_PKG="${PROJECT_DIR}/AppinfoInstaller.pkg"
IDENTIFIER="uk.org.russ"
VERSION="1.0.0"

echo "=========================================================="
echo " 📦 Creating macOS Installer Package (.pkg) for Appinfo"
echo "=========================================================="

echo "🔨 Building Release binary..."
xcodebuild -project "${PROJECT_DIR}/Untitled Project.xcodeproj" \
           -scheme "MyTool" \
           -configuration Release \
           -derivedDataPath "${BUILD_DIR}" \
           build > /dev/null

BINARY_PATH=$(find "${BUILD_DIR}/Build/Products/Release" -name "Appinfo" -type f -perm +111 2>/dev/null | head -n 1)

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH=$(find "${BUILD_DIR}" -name "Appinfo" -type f -perm +111 2>/dev/null | head -n 1)
fi

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: Could not locate built binary."
    exit 1
fi

echo "📁 Setting up package payload directory structure..."
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}/usr/local/bin"

# Install binary and symlink
cp -f "${BINARY_PATH}" "${PKG_ROOT}/usr/local/bin/appinfo"
chmod 755 "${PKG_ROOT}/usr/local/bin/appinfo"
ln -sf "appinfo" "${PKG_ROOT}/usr/local/bin/appinspect"

echo "📦 Packaging with pkgbuild..."
pkgbuild --root "${PKG_ROOT}" \
         --identifier "${IDENTIFIER}" \
         --version "${VERSION}" \
         --install-location "/" \
         "${OUTPUT_PKG}"

# Clean up temporary folders
rm -rf "${PKG_ROOT}"
rm -rf "${BUILD_DIR}"

echo ""
echo "=========================================================="
echo "✅ Package created successfully!"
echo "   ${OUTPUT_PKG}"
echo "=========================================================="
echo "You can now:"
echo " 1. Double-click '${OUTPUT_PKG}' in Finder to install via macOS GUI Installer."
echo " 2. Or install from Terminal using: sudo installer -pkg \"${OUTPUT_PKG}\" -target /"
echo " 3. Once installed, run either 'appinfo' or 'appinspect' in Terminal!"
echo "=========================================================="
