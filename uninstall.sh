#!/bin/bash
set -e

# ==============================================================================
# Appinfo Uninstaller Script
# Removes the installed binary from /usr/local/bin
# ==============================================================================

echo "=========================================================="
echo " 🗑️  Uninstalling Appinfo"
echo "=========================================================="

sudo rm -f "/usr/local/bin/appinfo"
sudo rm -f "/usr/local/bin/appinspect"

echo "✅ Appinfo and its appinspect alias have been removed from /usr/local/bin."
