import AppKit
import UniformTypeIdentifiers
import WebKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let fileURL: URL
    var openMarkdown: ((URL) -> Void)?
    var onClose: ((DocumentWindowController) -> Void)?

    private let webView: WKWebView
    private var watcher: FileWatcher?
    private var pendingScrollY: Double?
    private var loadGeneration = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true

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
        window.minSize = NSSize(width: 360, height: 300)
        window.contentView = webView
        window.tabbingMode = .preferred
        super.init(window: window)

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
        Task { @MainActor in
            let html = await MarkdownRenderer.documentRenderingDiagrams(markdown: markdown, title: title, fileURL: fileURL)
            guard generation == loadGeneration else { return }
            webView.loadHTMLString(html, baseURL: fileURL)
        }
    }

    private func reloadKeepingScroll() {
        webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
            self?.pendingScrollY = value as? Double
            self?.load()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window?.makeFirstResponder(webView)
        guard let y = pendingScrollY else { return }
        pendingScrollY = nil
        webView.evaluateJavaScript("window.scrollTo(0, \(y))")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        var target = URLComponents(url: url, resolvingAgainstBaseURL: true)
        target?.fragment = nil
        let page = target?.url ?? url
        if page.isFileURL, page.standardizedFileURL == fileURL {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        let markdownExtensions: Set = ["md", "markdown", "mdown", "mkd", "mkdn"]
        if page.isFileURL, markdownExtensions.contains(page.pathExtension.lowercased()) {
            openMarkdown?(page.standardizedFileURL)
        } else {
            NSWorkspace.shared.open(url)
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
        webView.pageZoom = min(webView.pageZoom + 0.1, 3)
    }

    @objc func zoomOut(_ sender: Any?) {
        webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
    }

    @objc func actualSize(_ sender: Any?) {
        webView.pageZoom = 1
    }

    @objc func printDocument(_ sender: Any?) {
        guard let window else { return }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
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
