#!/bin/zsh
#
# bundle_app.sh
# KireiMac
#
# 役割: Swift Package から Release ビルドとカスタム AppIcon.icns を生成し、macOS ネイティブの KireiMac.app バンドルを組み立てる。
# 存在意義: コマンド1つで Dock や Applications フォルダに配置可能なアイコン付きスタンドアロン .app を生成する。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="KireiMac"
APP_BUNDLE="${PROJECT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building ${APP_NAME} (Release)..."
swift build --disable-sandbox -c release --package-path "${PROJECT_DIR}"

BIN_PATH="$(swift build --disable-sandbox -c release --package-path "${PROJECT_DIR}" --show-bin-path)/${APP_NAME}"

echo "==> Creating ${APP_BUNDLE} structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "==> Generating AppIcon.icns..."
swift "${PROJECT_DIR}/scripts/generate_icon.swift" "${RESOURCES_DIR}"

# GitHub README 等でも使えるように docs/assets にもアプリアイコン PNG をコピー
mkdir -p "${PROJECT_DIR}/docs/assets"
cp "${RESOURCES_DIR}/AppIcon.png" "${PROJECT_DIR}/docs/assets/icon.png"

# Finder / Dock 用に KireiMac.app バンドル自体にもカスタムアイコン属性を付与する
swift -e '
import AppKit
let appPath = CommandLine.arguments[1]
let iconPath = CommandLine.arguments[2]
if let img = NSImage(contentsOfFile: iconPath) {
    NSWorkspace.shared.setIcon(img, forFile: appPath, options: [])
}
' "${APP_BUNDLE}" "${RESOURCES_DIR}/AppIcon.png"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>CFBundleDisplayName</key>
    <string>KireiMac</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.kireimac.KireiMac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# アドホック署名（ローカル実行時のGatekeeper警告抑止）
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

touch "${APP_BUNDLE}"

echo "==> Successfully created: ${APP_BUNDLE}"
