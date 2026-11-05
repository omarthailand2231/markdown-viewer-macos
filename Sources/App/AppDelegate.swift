import AppKit
import UniformTypeIdentifiers

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [DocumentWindowController] = []
    private var openedAtLaunch = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--make-default") {
            DefaultHandler.makeDefault { error in
                print(error.map { "Could not set default: \($0.localizedDescription)" } ?? "Markdown Viewer is now the default app for Markdown files")
                exit(error == nil ? 0 : 1)
            }
            return
        }
        DefaultHandler.claimOnFirstLaunch()
        DispatchQueue.main.async {
            if !self.openedAtLaunch && self.controllers.isEmpty { self.openDocument(nil) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAtLaunch = true
        urls.forEach(open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openDocument(nil) }
        return true
    }

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        if let existing = controllers.first(where: { $0.fileURL == url }) {
            existing.showWindow(nil)
            return
        }
        let controller = DocumentWindowController(fileURL: url)
        controller.openMarkdown = { [weak self] in self?.open($0) }
        controller.onClose = { [weak self] closed in self?.controllers.removeAll { $0 === closed } }
        if let last = controllers.last?.window {
            controller.window?.setFrameTopLeftPoint(last.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else if let window = controller.window {
            if !window.setFrameUsingName(DocumentWindowController.frameName) { window.center() }
            window.setFrameAutosaveName(DocumentWindowController.frameName)
        }
        controllers.append(controller)
        controller.showWindow(nil)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [DefaultHandler.markdown, .plainText]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else {
            if controllers.isEmpty { NSApp.terminate(nil) }
            return
        }
        panel.urls.forEach(open)
    }

    @objc func makeDefault(_ sender: Any?) {
        DefaultHandler.makeDefault { error in
            let alert = NSAlert()
            if let error {
                alert.messageText = "Couldn't make Markdown Viewer the default"
                alert.informativeText = error.localizedDescription
            } else {
                alert.messageText = "Markdown Viewer now opens .md files"
            }
            alert.runModal()
        }
    }
}

enum DefaultHandler {
    static let markdown = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
    private static let claimedKey = "claimedMarkdownDefault"

    static func claimOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: claimedKey) else { return }
        UserDefaults.standard.set(true, forKey: claimedKey)
        makeDefault { _ in }
    }

    static func makeDefault(completion: @escaping (Error?) -> Void) {
        if let bundleID = Bundle.main.bundleIdentifier {
            LSSetDefaultRoleHandlerForContentType(markdown.identifier as CFString, .all, bundleID as CFString)
        }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdown) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }
}
