#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/MarkdownViewer.app
EXT="$APP/Contents/PlugIns/MarkdownPreview.appex"
TARGET="$(uname -m)-apple-macos14.0"
KEYCHAIN="$HOME/Library/Keychains/dev-signing.keychain-db"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"

swiftc -O -parse-as-library -swift-version 5 -target "$TARGET" \
  Sources/Shared/*.swift Sources/App/*.swift \
  -o "$APP/Contents/MacOS/MarkdownViewer"

swiftc -O -parse-as-library -swift-version 5 -target "$TARGET" -application-extension \
  -module-name MarkdownPreview \
  Sources/Shared/*.swift Sources/QuickLook/*.swift \
  -framework QuickLookUI \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$EXT/Contents/MacOS/MarkdownPreview"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/QuickLook-Info.plist "$EXT/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swiftc -O scripts/make-icon.swift -o build/make-icon
  build/make-icon build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$EXT/Contents/Resources"
cp Vendor/katex/katex.min.js "$APP/Contents/Resources/"
cp Vendor/katex/katex.min.js "$EXT/Contents/Resources/"
cp Vendor/mermaid/mermaid.min.js "$APP/Contents/Resources/"
cp Vendor/mermaid/mermaid.min.js "$EXT/Contents/Resources/"

./scripts/setup-signing.sh
codesign --force --sign "Local Code Signing" --keychain "$KEYCHAIN" \
  --entitlements Resources/QuickLook.entitlements "$EXT" >/dev/null
codesign --force --sign "Local Code Signing" --keychain "$KEYCHAIN" "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MarkdownViewer 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/MarkdownViewer.app
  cp -R "$APP" ~/Applications/
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -f -R ~/Applications/MarkdownViewer.app
  pluginkit -a ~/Applications/MarkdownViewer.app/Contents/PlugIns/MarkdownPreview.appex
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
  echo "Installed ~/Applications/MarkdownViewer.app"
fi
