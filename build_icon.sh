#!/bin/bash
#
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright © 2026 Jia Liu
#
# Compile PixAI.icon to Assets.car for macOS 27
# Run this locally after updating the icon, then commit the result.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Compiling icon..."

# Create output directory
mkdir -p "$SCRIPT_DIR/Resources/Compiled"

# Compile .icon to Assets.car
xcrun actool "$SCRIPT_DIR/Resources/PixAI.icon" \
    --compile "$SCRIPT_DIR/Resources/Compiled" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon PixAI \
    --output-partial-info-plist /dev/null

echo "✅ Icon compiled: Resources/Compiled/Assets.car"
echo ""
echo "   Now commit and push:"
echo "     git add Resources/Compiled/Assets.car"
echo "     git commit -m 'Update compiled icon'"
echo "     git push"