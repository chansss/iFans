#!/bin/bash
# 以 Release 配置打包 iFan，并安装/替换到「应用程序」目录。
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="iFan.xcodeproj"
SCHEME="iFan"
CONFIG="Release"
DERIVED="build"
DEST="$HOME/Applications"
APP_NAME="iFan.app"
BUILT_APP="${DERIVED}/Build/Products/${CONFIG}/${APP_NAME}"

has_full_xcode() {
  local dev_dir
  dev_dir="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$dev_dir" && "$dev_dir" != "/Library/Developer/CommandLineTools" && -x "$dev_dir/usr/bin/xcodebuild" ]]
}

build_with_xcode() {
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" clean build
}

build_with_swiftc() {
  local app="$BUILT_APP"
  local contents="$app/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"
  local iconset="$resources/AppIcon.iconset"
  local arch
  arch="$(uname -m)"

  /bin/rm -rf "$DERIVED"
  mkdir -p "$macos" "$resources"

  swiftc -O -parse-as-library \
    -target "${arch}-apple-macosx14.0" \
    -o "$macos/iFan" \
    iFan/*.swift \
    -framework SwiftUI \
    -framework AppKit \
    -framework IOKit

  cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>iFan</string>
  <key>CFBundleExecutable</key><string>iFan</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.ifan.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>iFan</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

  if command -v iconutil >/dev/null 2>&1; then
    mkdir -p "$iconset"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_16x16.png "$iconset/icon_16x16.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_32x32.png "$iconset/icon_16x16@2x.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_32x32.png "$iconset/icon_32x32.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_128x128.png "$iconset/icon_128x128.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_256x256.png "$iconset/icon_128x128@2x.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_256x256.png "$iconset/icon_256x256.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_512x512.png "$iconset/icon_256x256@2x.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_512x512.png "$iconset/icon_512x512.png"
    cp iFan/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png "$iconset/icon_512x512@2x.png"
    iconutil -c icns "$iconset" -o "$resources/AppIcon.icns" || true
    /bin/rm -rf "$iconset"
  fi

  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$app"
  fi
}

echo "==> 退出正在运行的 iFan（如有）"
pkill -x iFan 2>/dev/null || true

echo "==> 清理并以 ${CONFIG} 配置编译"
if has_full_xcode; then
  build_with_xcode
else
  echo "==> 未检测到完整 Xcode，使用 swiftc 命令行 fallback 构建"
  build_with_swiftc
fi

if [ ! -d "$BUILT_APP" ]; then
  echo "构建产物不存在：${BUILT_APP}" >&2
  exit 1
fi

echo "==> 替换 ${DEST}/${APP_NAME}"
mkdir -p "$DEST"
/bin/rm -rf "${DEST}/${APP_NAME}" 2>/dev/null || true
cp -R "$BUILT_APP" "$DEST/"

echo "==> 完成：${DEST}/${APP_NAME}"
echo "可执行：open \"${DEST}/${APP_NAME}\""
