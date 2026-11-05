#!/usr/bin/env bash
set -uo pipefail

APP="$HOME/Applications/MarkdownViewer.app"
EXTENSION_ID="io.github.omarthailand2231.markdownviewer.quicklook"
FAILED=0
ok() { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; FAILED=1; }

echo "Markdown Viewer doctor"

if [[ -d "$APP" ]]; then ok "App installed: $APP"; else bad "App missing. Run: ./scripts/build.sh --install"; fi

if codesign --verify --deep --strict "$APP" 2>/dev/null; then ok "Code signature valid"; else bad "Code signature invalid. Rebuild: ./scripts/build.sh --install"; fi

LINE="$(pluginkit -m -v -i "$EXTENSION_ID" 2>/dev/null | head -1)"
if [[ -z "$LINE" ]]; then
  bad "Quick Look extension not registered. Run: pluginkit -a \"$APP/Contents/PlugIns/MarkdownPreview.appex\" && qlmanage -r"
elif [[ "$LINE" == -* ]]; then
  bad "Quick Look extension is disabled. Enable 'Markdown Preview' in System Settings → General → Login Items & Extensions → Quick Look"
else
  ok "Quick Look extension registered and enabled"
fi

PROBE="$(mktemp -d)/probe.md"
echo "# probe" > "$PROBE"
DEFAULT="$(osascript -l JavaScript -e "ObjC.import('AppKit'); var u = \$.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL(\$.NSURL.fileURLWithPath('$PROBE')); u.isNil() ? 'none' : u.path.js" 2>/dev/null)"
rm -rf "$(dirname "$PROBE")"
if [[ "$DEFAULT" == "$APP" ]]; then
  ok "Default app for .md files"
else
  bad "Default app for .md is '$DEFAULT'. To change: \"$APP/Contents/MacOS/MarkdownViewer\" --make-default"
fi

for resource in katex.min.js mermaid.min.js; do
  if [[ -f "$APP/Contents/Resources/$resource" && -f "$APP/Contents/PlugIns/MarkdownPreview.appex/Contents/Resources/$resource" ]]; then
    ok "Bundled $resource"
  else
    bad "Missing $resource in the app or extension. Rebuild: ./scripts/build.sh --install"
  fi
done

exit $FAILED
