#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Markdown Viewer.app"
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
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  INSTALLED="$HOME/Applications/Markdown Viewer.app"
  PROBE="$(mktemp -d)/probe.md"
  echo "# probe" > "$PROBE"
  CURRENT_DEFAULT="$(osascript -l JavaScript -e "ObjC.import('AppKit'); var u = \$.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL(\$.NSURL.fileURLWithPath('$PROBE')); u.isNil() ? '' : \$.NSBundle.bundleWithURL(u).bundleIdentifier.js" 2>/dev/null || true)"
  rm -rf "$(dirname "$PROBE")"
  pkill -x MarkdownViewer 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  for LEGACY in "$HOME/Applications/MarkdownViewer.app" "$PWD/build/MarkdownViewer.app"; do
    if [[ -d "$LEGACY" ]]; then
      pluginkit -r "$LEGACY/Contents/PlugIns/MarkdownPreview.appex" 2>/dev/null || true
      "$LSREGISTER" -u "$LEGACY" 2>/dev/null || true
      rm -rf "$LEGACY"
    fi
  done
  rm -rf "$INSTALLED"
  ditto "$APP" "$INSTALLED"
  pluginkit -r "$PWD/$EXT" 2>/dev/null || true
  "$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
  rm -rf "$APP"
  "$LSREGISTER" -f -R "$INSTALLED"
  pluginkit -a "$INSTALLED/Contents/PlugIns/MarkdownPreview.appex"
  pluginkit -e use -i io.github.omarthailand2231.markdownviewer.quicklook
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
  if [[ "$CURRENT_DEFAULT" == "io.github.omarthailand2231.markdownviewer" ]]; then
    "$INSTALLED/Contents/MacOS/MarkdownViewer" --make-default >/dev/null
  fi
  echo "Installed $INSTALLED"
fi
