import AppKit
import UniformTypeIdentifiers
import WebKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, NSSearchFieldDelegate {
    static let frameName = "MarkdownViewerDocument"
    private static let zoomKey = "pageZoom"
    private static let markdownExtensions: Set = ["md", "markdown", "mdown", "mkd", "mkdn"]

    let fileURL: URL
    var openMarkdown: ((URL) -> Void)?
    var onClose: ((DocumentWindowController) -> Void)?

    private let webView: WKWebView
    private let findField = NSSearchField()
    private let findStatus = NSTextField(labelWithString: "")
    private var findBar: NSView!
    private var watcher: FileWatcher?
    private var pendingScrollY: Double?
    private var loadGeneration = 0
    private var pageReady = false
    private var diagramSources: [String] = []
    private var renderedDiagrams: [String: String]?

    init(fileURL: URL) {
        self.fileURL = fileURL
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.alphaValue = 0
        let savedZoom = UserDefaults.standard.double(forKey: Self.zoomKey)
        webView.pageZoom = savedZoom > 0 ? savedZoom : 1

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(920, visible.width * 0.9), height: min(1100, visible.height * 0.92))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.lastPathComponent
        window.representedURL = fileURL
        window.minSize = NSSize(width: 320, height: 240)
        window.tabbingMode = .preferred
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 13 / 255, green: 17 / 255, blue: 23 / 255, alpha: 1)
                : .white
        }
        super.init(window: window)

        findBar = makeFindBar()
        let stack = NSStackView(views: [findBar, webView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = stack

        window.delegate = self
        webView.navigationDelegate = self
        load()
        watcher = FileWatcher(url: fileURL) { [weak self] in self?.reloadKeepingScroll() }
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        onClose?(self)
    }

    private func load() {
        loadGeneration += 1
        let generation = loadGeneration
        let title = fileURL.lastPathComponent
        let markdown: String
        do {
            markdown = try MarkdownFile.read(fileURL)
        } catch {
            markdown = "**Couldn't read \(title)**\n\n\(error.localizedDescription)"
        }
        let sources = MarkdownRenderer.mermaidSources(in: markdown)
        let cached = MermaidRenderer.shared.cached(sources)
        let pending = cached.count < Set(sources).count
        pageReady = false
        diagramSources = pending ? sources : []
        renderedDiagrams = nil
        let html = MarkdownRenderer.document(markdown: markdown, title: title, fileURL: fileURL, diagrams: cached, diagramsPending: pending)
        webView.loadHTMLString(html, baseURL: fileURL)
        guard pending else { return }
        Task { @MainActor in
            let rendered = await MermaidRenderer.shared.render(sources)
            guard generation == loadGeneration else { return }
            renderedDiagrams = rendered
            injectDiagramsIfReady()
        }
    }

    private func injectDiagramsIfReady() {
        guard pageReady, let rendered = renderedDiagrams, !diagramSources.isEmpty else { return }
        let list: [Any] = diagramSources.map { rendered[$0] ?? NSNull() }
        guard let data = try? JSONSerialization.data(withJSONObject: list),
              let json = String(data: data, encoding: .utf8)
        else { return }
        diagramSources = []
        webView.evaluateJavaScript("""
        (function (diagrams) {
          document.querySelectorAll("[data-mermaid]").forEach(function (node) {
            var html = diagrams[Number(node.getAttribute("data-mermaid"))];
            if (html) { node.outerHTML = html; } else { node.classList.remove("mermaid-pending"); node.removeAttribute("data-mermaid"); }
          });
        })(\(json));
        """)
    }

    private func reloadKeepingScroll() {
        webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
            self?.pendingScrollY = value as? Double
            self?.load()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        injectDiagramsIfReady()
        if let y = pendingScrollY {
            pendingScrollY = nil
            webView.evaluateJavaScript("window.scrollTo({ top: \(y), behavior: 'instant' })")
        }
        if webView.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                webView.animator().alphaValue = 1
            }
            if findBar.isHidden { window?.makeFirstResponder(webView) }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        var target = URLComponents(url: url, resolvingAgainstBaseURL: true)
        target?.fragment = nil
        let page = target?.url ?? url
        let samePage = page.isFileURL && page.standardizedFileURL == fileURL
        if samePage || (navigationAction.navigationType != .linkActivated && !page.isFileURL) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if page.isFileURL, Self.markdownExtensions.contains(page.pathExtension.lowercased()) {
            openMarkdown?(page.standardizedFileURL)
        } else if navigationAction.navigationType == .linkActivated || page.isFileURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func makeFindBar() -> NSView {
        findField.placeholderString = "Find"
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findFieldChanged(_:))
        findField.sendsSearchStringImmediately = true
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        findStatus.textColor = .secondaryLabelColor
        findStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let previous = NSButton(
            image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match") ?? NSImage(),
            target: self,
            action: #selector(findPreviousMatch(_:))
        )
        let next = NSButton(
            image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match") ?? NSImage(),
            target: self,
            action: #selector(findNextMatch(_:))
        )
        let done = NSButton(title: "Done", target: self, action: #selector(closeFind(_:)))
        for button in [previous, next, done] {
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [findField, findStatus, spacer, previous, next, done])
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let separator = NSBox()
        separator.boxType = .separator
        let bar = NSStackView(views: [row, separator])
        bar.orientation = .vertical
        bar.spacing = 0
        bar.alignment = .width
        bar.isHidden = true
        return bar
    }

    @objc func showFind(_ sender: Any?) {
        findBar.isHidden = false
        window?.makeFirstResponder(findField)
        findField.selectText(nil)
    }

    @objc func closeFind(_ sender: Any?) {
        findBar.isHidden = true
        findStatus.stringValue = ""
        window?.makeFirstResponder(webView)
    }

    @objc func findNextMatch(_ sender: Any?) {
        if findBar.isHidden { showFind(nil) }
        find(backwards: false)
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        if findBar.isHidden { showFind(nil) }
        find(backwards: true)
    }

    @objc private func findFieldChanged(_ sender: Any?) {
        find(backwards: false)
    }

    private func find(backwards: Bool) {
        let text = findField.stringValue
        guard !text.isEmpty else {
            findStatus.stringValue = ""
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(text, configuration: configuration) { [weak self] result in
            self?.findStatus.stringValue = result.matchFound ? "" : "No matches"
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            closeFind(nil)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        default:
            return false
        }
    }

    @objc func editInTextEditor(_ sender: Any?) {
        let ownID = Bundle.main.bundleIdentifier
        let editor = [UTType.plainText, .sourceCode]
            .compactMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            .first { Bundle(url: $0)?.bundleIdentifier != ownID }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        guard let editor else { return }
        NSWorkspace.shared.open([fileURL], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func showInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    @objc func reloadDocument(_ sender: Any?) {
        reloadKeepingScroll()
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(webView.pageZoom + 0.1)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(webView.pageZoom - 0.1)
    }

    @objc func actualSize(_ sender: Any?) {
        setZoom(1)
    }

    private func setZoom(_ zoom: CGFloat) {
        let clamped = min(max(zoom, 0.5), 3)
        webView.pageZoom = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Self.zoomKey)
    }

    @objc func printDocument(_ sender: Any?) {
        guard let window else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var stopped = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start(retries: 0)
    }

    func stop() {
        stopped = true
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    private func start(retries: Int) {
        guard !stopped else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            if retries < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start(retries: retries + 1) }
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                source.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.start(retries: 0) }
            }
            self.scheduleChange()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
