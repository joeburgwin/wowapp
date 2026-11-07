#!/usr/bin/env bash
# Builds dist/ForeverXP-<version>.zip ready to drop into Interface/AddOns.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(grep -m1 '^## Version:' ForeverXP/ForeverXP.toc | awk '{print $3}')
mkdir -p dist
rm -f "dist/ForeverXP-${version}.zip"
zip -qr "dist/ForeverXP-${version}.zip" ForeverXP -x '*.DS_Store'
echo "dist/ForeverXP-${version}.zip"
