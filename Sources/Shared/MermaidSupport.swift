import Foundation
import WebKit

extension MarkdownRenderer {
    @MainActor
    static func documentRenderingDiagrams(markdown: String, title: String, fileURL: URL?) async -> String {
        let sources = mermaidSources(in: markdown)
        let diagrams = sources.isEmpty ? [:] : await MermaidRenderer.shared.render(sources)
        return document(markdown: markdown, title: title, fileURL: fileURL, diagrams: diagrams)
    }
}

@MainActor
final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    private enum LoadState { case idle, loading, ready, failed }

    private var webView: WKWebView?
    private var state = LoadState.idle
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private var cache: [String: String] = [:]

    func render(_ sources: [String]) async -> [String: String] {
        var missing: [String] = []
        for source in sources where cache[source] == nil && !missing.contains(source) {
            missing.append(source)
        }
        if !missing.isEmpty, await ensureLoaded(), let webView {
            let result = try? await webView.callAsyncJavaScript(
                Self.renderScript,
                arguments: ["sources": missing],
                contentWorld: .page
            )
            if let pairs = result as? [Any] {
                for (source, value) in zip(missing, pairs) {
                    guard let pair = value as? [String], pair.count == 2 else { continue }
                    cache[source] = "<div class=\"mermaid-diagram\"><div class=\"mermaid-light\">\(pair[0])</div><div class=\"mermaid-dark\">\(pair[1])</div></div>"
                }
            }
        }
        var rendered: [String: String] = [:]
        for source in sources {
            if let html = cache[source] { rendered[source] = html }
        }
        return rendered
    }

    private func ensureLoaded() async -> Bool {
        switch state {
        case .ready:
            return true
        case .failed:
            return false
        case .loading:
            return await withCheckedContinuation { waiters.append($0) }
        case .idle:
            let environment = ProcessInfo.processInfo.environment["MDVIEWER_MERMAID"].map { URL(fileURLWithPath: $0) }
            guard let url = environment ?? Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8)
            else {
                state = .failed
                return false
            }
            state = .loading
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
            webView.navigationDelegate = self
            self.webView = webView
            webView.loadHTMLString("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>", baseURL: nil)
            return await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func finishLoading(_ ok: Bool) {
        state = ok ? .ready : .failed
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: ok) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        self.webView = nil
        state = .idle
    }

    private static let renderScript = """
    const font = '-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif';
    const results = [];
    let counter = 0;
    for (const code of sources) {
      try {
        const pair = [];
        for (const theme of ["default", "dark"]) {
          mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: theme, fontFamily: font });
          const id = "mdv" + theme + (counter++) + Math.random().toString(36).slice(2, 8);
          const { svg } = await mermaid.render(id, code);
          pair.push(svg);
        }
        results.push(pair);
      } catch (error) {
        results.push(null);
      }
      document.querySelectorAll("body > *").forEach((node) => node.remove());
    }
    return results;
    """
}
