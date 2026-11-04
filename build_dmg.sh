#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=== 1. 构建 release 二进制（Universal: arm64 + x86_64）==="
swift build -c release --arch arm64 --arch x86_64

APP_NAME="PerfTicker"
DIST_DIR="$DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="PerfTicker-macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "=== 2. 创建 $APP_NAME.app 包 ==="
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$DIR/.build/release/PerfTicker" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat << 'PLIST' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PerfTicker</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.qiusui.perfticker</string>
    <key>CFBundleName</key>
    <string>性能行情终端</string>
    <key>CFBundleDisplayName</key>
    <string>性能行情终端</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.0</string>
    <key>CFBundleVersion</key>
    <string>1.5.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "=== 3. 签名应用包 ==="
# 有 Developer ID 证书就用它（可再走 notarytool 公证对外分发），否则退回本地 ad-hoc
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$DEV_ID" ]; then
    echo "使用 Developer ID: $DEV_ID"
    codesign --force --options runtime --sign "$DEV_ID" "$APP_BUNDLE"
else
    echo "未找到 Developer ID 证书，使用本地 ad-hoc 签名（对外分发会触发 Gatekeeper 提示）"
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "=== 校验产物架构 ==="
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "=== 4. 生成 DMG 安装包 ==="
DMG_STAGING="$DIST_DIR/dmg_staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "=== 打包完成 ==="
ls -lh "$DMG_PATH"
