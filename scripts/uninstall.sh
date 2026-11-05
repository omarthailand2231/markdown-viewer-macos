#!/usr/bin/env bash
set -uo pipefail

APP="$HOME/Applications/Markdown Viewer.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

pkill -x MarkdownViewer 2>/dev/null || true
for BUNDLE in "$APP" "$HOME/Applications/MarkdownViewer.app"; do
  if [[ -d "$BUNDLE" ]]; then
    pluginkit -r "$BUNDLE/Contents/PlugIns/MarkdownPreview.appex" 2>/dev/null || true
    "$LSREGISTER" -u "$BUNDLE" 2>/dev/null || true
    rm -rf "$BUNDLE"
  fi
done
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
echo "Removed $APP and its Quick Look extension."

if [[ "${1:-}" == "--remove-signing" ]]; then
  security delete-keychain "$HOME/Library/Keychains/dev-signing.keychain-db" 2>/dev/null || true
  rm -f "$HOME/.config/dev-signing/keychain-password"
  echo "Removed the 'Local Code Signing' keychain."
else
  echo "Kept the 'Local Code Signing' keychain (other locally built apps may use it). Remove it with: ./scripts/uninstall.sh --remove-signing"
fi
