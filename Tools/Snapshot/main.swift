import AppKit
import WebKit

final class Snapshotter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: NSWindow
    private let output: URL
    private let fullPage: Bool

    init(file: URL, output: URL, dark: Bool, width: CGFloat, height: CGFloat, fullPage: Bool) {
        self.output = output
        self.fullPage = fullPage
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
        window.orderFront(nil)
        let markdown = (try? MarkdownFile.read(file)) ?? ""
        let webView = webView
        Task { @MainActor in
            let html = await MarkdownRenderer.documentRenderingDiagrams(markdown: markdown, title: file.lastPathComponent, fileURL: file)
            webView.loadHTMLString(html, baseURL: file)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.scrollHeight") { value, _ in
            if self.fullPage, let height = value as? CGFloat {
                self.window.setContentSize(NSSize(width: webView.frame.width, height: height))
                webView.frame.size.height = height
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.capture() }
        }
    }

    private func capture() {
        webView.takeSnapshot(with: nil) { image, _ in
            guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            try? png.write(to: self.output)
            exit(0)
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: snapshot <file.md> <out.png> [--dark] [--width N] [--height N] [--full]")
    exit(2)
}
func value(_ flag: String, _ fallback: CGFloat) -> CGFloat {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count, let number = Double(arguments[index + 1]) else { return fallback }
    return CGFloat(number)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let snapshotter = Snapshotter(
    file: URL(fileURLWithPath: arguments[1]),
    output: URL(fileURLWithPath: arguments[2]),
    dark: arguments.contains("--dark"),
    width: value("--width", 900),
    height: value("--height", 1100),
    fullPage: arguments.contains("--full")
)
app.run()
