#!/bin/zsh
#
# package_release.sh
# KireiMac
#
# 役割: dist/KireiMac.app から配布用の KireiMac.dmg (Applicationsシンボリックリンク同梱) と KireiMac.app.zip を生成する。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="KireiMac"
VERSION="${1:-v1.0.0}"
DIST_DIR="${PROJECT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_STAGING="${DIST_DIR}/dmg_staging"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.zip"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    zsh "${PROJECT_DIR}/scripts/bundle_app.sh"
fi

echo "==> Creating ${ZIP_PATH}..."
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Creating ${DMG_PATH}..."
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_STAGING}"

echo "==> Release artifacts ready:"
ls -lh "${DMG_PATH}" "${ZIP_PATH}"
