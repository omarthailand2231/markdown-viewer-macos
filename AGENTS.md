# AGENTS.md

A complete guide for AI agents (Claude Code, Codex, Cursor, Copilot, Gemini CLI, …) to **install**, **use**, **verify**, **uninstall** and **develop** Markdown Viewer for macOS on a user's Mac.

Markdown Viewer is a native macOS app plus a Finder Quick Look extension. Once it is installed, double-clicking a `.md` file and pressing Space on it in Finder both show the document fully formatted, with tables, task lists, footnotes, callouts, LaTeX math, Mermaid diagrams and diffs, in light or dark mode following macOS.

---

## 1. Install for the user

Requirements: macOS 14+, Apple silicon or Intel, the Xcode **Command Line Tools** (full Xcode is not needed), and `git`.

```sh
xcode-select -p >/dev/null 2>&1 || xcode-select --install
git clone https://github.com/omarthailand2231/markdown-viewer-macos.git ~/Developer/markdown-viewer-macos
cd ~/Developer/markdown-viewer-macos
./scripts/build.sh --install
./scripts/doctor.sh
```

`xcode-select --install` opens a system dialog the user has to click through. Wait for it to finish before building.

A successful `doctor.sh` prints seven ✓ lines and exits with code 0:

```text
Markdown Viewer doctor
  ✓ App installed: /Users/<you>/Applications/MarkdownViewer.app
  ✓ Code signature valid
  ✓ Quick Look extension registered and enabled
  ✓ Default app for .md files
  ✓ Only one copy registered with macOS
  ✓ Bundled katex.min.js
  ✓ Bundled mermaid.min.js
```

Right after a fresh install, "Default app for .md files" can still fail, because the app claims `.md` the first time it launches. Set it explicitly (only if the user wants it as their default):

```sh
~/Applications/MarkdownViewer.app/Contents/MacOS/MarkdownViewer --make-default
```

### What the install changes (tell the user)

| Change | Where |
|:-------|:------|
| The app and its Quick Look extension | `~/Applications/MarkdownViewer.app` |
| Quick Look registration | `pluginkit` database (per user) |
| Default app for `net.daringfireball.markdown` (`.md`, `.markdown`) | Launch Services, on first launch or `--make-default` |
| A self-signed code-signing certificate "Local Code Signing", created once | Keychain `~/Library/Keychains/dev-signing.keychain-db`, password in `~/.config/dev-signing/keychain-password` |

There are no daemons, login items, network services, analytics or admin prompts. The certificate exists only because macOS refuses to load unsigned Quick Look extensions. It never leaves the Mac.

---

## 2. Use it

| Task | Command or action |
|:-----|:------------------|
| Open a file in the viewer | `open -a ~/Applications/MarkdownViewer.app path/to/file.md` (or just `open file.md` once it is the default) |
| Open several files as tabs | `open -a ~/Applications/MarkdownViewer.app a.md b.md` |
| Quick Look preview | Select the file in Finder and press Space. `open -R file.md` reveals it in Finder for the user. |
| Make it the default for `.md` | `~/Applications/MarkdownViewer.app/Contents/MacOS/MarkdownViewer --make-default`, or the app menu → *Make Default for Markdown Files* |
| Render a Markdown file to PNG without opening a window | `./scripts/snapshot.sh file.md out.png [--dark] [--full] [--width 900] [--height 1100]` (run from the repo) |

The viewer reloads automatically when the file changes on disk, so an agent can keep editing a `.md` file while the user watches it update. Inside the app: ⌘E opens the file in the user's text editor, ⇧⌘R reveals it in Finder, ⌘P prints or saves a PDF, and ⌘= / ⌘- / ⌘0 zoom.

> [!WARNING]
> Do not use `qlmanage -p` to test the preview. On current macOS it crashes inside Apple's own tool when it hosts a modern (app-extension) Quick Look preview. Use Finder + Space, or `./scripts/snapshot.sh` for a headless render made by the same code.

---

## 3. Writing Markdown that renders well here

Everything below renders in both the app and Quick Look.

| Feature | Syntax |
|:--------|:-------|
| GitHub tables with alignment | `\| Left \| Center \| Right \|` then `\|:--\|:-:\|--:\|` |
| Task lists | `- [ ] todo` / `- [x] done` |
| Callouts | `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]` on the first line of a quote |
| Footnotes | `text[^1]` … `[^1]: The note.` (indent continuation lines by 4 spaces) |
| Inline math | `$E = mc^2$` or `\(E = mc^2\)` |
| Display math | `$$ … $$` on its own lines, `\[ … \]`, or a ` ```math ` fence |
| Mermaid diagrams | a ` ```mermaid ` fence (flowchart, sequence, class, state, gantt, pie, …) |
| Code changes | a ` ```diff ` or ` ```patch ` fence; `+` lines green, `-` lines red, `@@` hunks highlighted |
| Local images | `![alt](relative/path.png)` or `<img src="relative/path.png">`; both are embedded |
| Front matter | YAML between `---` lines at the top; shown as a muted block |

Example:

````markdown
> [!TIP]
> The integral $\int_0^1 x\,dx = \tfrac12$ renders inline.

```mermaid
flowchart LR
  A[Edit .md] --> B[Viewer reloads]
```

```diff
- old line
+ new line
```
````

Dollar amounts such as `$5 and $10` stay plain text. To print a literal dollar sign right before a letter, write `\$`.

---

## 4. Troubleshooting

| Symptom | Fix |
|:--------|:----|
| Space in Finder still shows plain text | `qlmanage -r && qlmanage -r cache && killall Finder`, then check System Settings → General → Login Items & Extensions → Quick Look → **Markdown Preview** is on. Run `./scripts/doctor.sh`. |
| Settings seem lost after a restart or login | Run `./scripts/doctor.sh`. Everything is saved on disk by macOS (default app via Launch Services, the extension via `pluginkit -e use`). The usual cause is a second registered copy of the app (doctor flags it); unregister it with `lsregister -u <path>`. Then run `--make-default`. |
| `.md` files still open in TextEdit or Xcode | `~/Applications/MarkdownViewer.app/Contents/MacOS/MarkdownViewer --make-default`, or Finder → Get Info → Open with → Change All… |
| `swiftc: command not found` / `xcrun: error` | Install the Command Line Tools: `xcode-select --install` |
| Signing fails | `./scripts/setup-signing.sh` is idempotent. Delete `~/Library/Keychains/dev-signing.keychain-db` and `~/.config/dev-signing/keychain-password`, then rebuild. |
| Math shows as raw TeX in red | KaTeX is missing from the bundle. Rebuild with `./scripts/build.sh --install` and check `doctor.sh`. |
| A Mermaid block shows as code | The diagram has a syntax error (Mermaid rejected it) or `mermaid.min.js` is missing (see `doctor.sh`). |
| App opens behind other windows | `open -a ~/Applications/MarkdownViewer.app` brings it forward. |

---

## 5. Uninstall

```sh
./scripts/uninstall.sh                    # removes the app and the Quick Look extension
./scripts/uninstall.sh --remove-signing   # also deletes the "Local Code Signing" keychain
```

macOS then goes back to its previous default for `.md` files.

---

## 6. Develop

### Layout

```text
Sources/Shared/MarkdownRenderer.swift  Markdown → HTML (Apple's parser), stylesheet, tables, footnotes, callouts, diffs, images
Sources/Shared/MathSupport.swift       finds math/mermaid outside code, KaTeX in JavaScriptCore → MathML
Sources/Shared/MermaidSupport.swift    hidden WKWebView renders Mermaid → light + dark SVG, cached per source
Sources/App/                           AppKit app: windows/tabs, live reload, menus, --make-default
Sources/QuickLook/PreviewProvider.swift  sandboxed data-based Quick Look extension (QLPreviewProvider)
Resources/                             Info.plists and the extension's entitlements
Vendor/katex, Vendor/mermaid           pinned third-party scripts (MIT) with their licenses
Tests/main.swift, Tests/Fixtures/      renderer test runner and fixtures
Tools/Snapshot/                        headless Markdown → PNG renderer
scripts/                               build, test, snapshot, doctor, uninstall, setup-signing
```

### Commands

```sh
./scripts/test.sh                       # 90 checks: every syntax above, math, real Mermaid rendering, edge cases, speed
./scripts/snapshot.sh Tests/Fixtures/everything.md /tmp/light.png --full
./scripts/snapshot.sh Tests/Fixtures/everything.md /tmp/dark.png --full --dark
./scripts/build.sh                      # build + sign into build/
./scripts/build.sh --install            # also install, register, reset Quick Look
./scripts/doctor.sh
```

### Rules for changes

1. Run `./scripts/test.sh` and keep it at 0 failures. Add a fixture line and a check for any new syntax.
2. Look at the result: render the fixtures with `snapshot.sh` in **both** light and `--dark` and inspect the PNGs before claiming a visual change works.
3. Both targets compile from `Sources/Shared`: the app is not sandboxed, but the Quick Look extension **is**. Shared code must work in the sandbox: read only the previewed file and its folder, write nothing, and add no new entitlements without a reason.
4. Quick Look previews are data-based HTML: **no JavaScript runs in the preview**. Anything dynamic (math, diagrams) must become static HTML/SVG/MathML in Swift before the page is returned. The app's page also runs with page JavaScript disabled.
5. No new dependencies or package managers. Third-party code goes in `Vendor/<name>/` at a pinned version with its `LICENSE`, copied into both bundles by `scripts/build.sh`.
6. Keep code free of explanatory comments; explain design in README.md or this file.
7. Bundle identifiers: app `io.github.omarthailand2231.markdownviewer`, extension `….quicklook`. Changing them re-registers the extension and resets the default-app choice.
8. `./scripts/build.sh --install` moves the bundle out of `build/` and unregisters that path, so macOS only ever knows one copy (two copies with the same bundle ID can make macOS pick the wrong one after a restart). The app claims Markdown with `LSHandlerRank` **Owner**, and `--make-default` writes the choice through both `LSSetDefaultRoleHandlerForContentType` and `NSWorkspace.setDefaultApplication`.
9. After changing the extension, run `./scripts/build.sh --install`. Finder may keep an old preview until `qlmanage -r cache` runs or Finder relaunches.
