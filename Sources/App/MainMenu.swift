import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        let name = "Markdown Viewer"

        main.addSubmenu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Make Default for Markdown Files", #selector(AppDelegate.makeDefault(_:))),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ])

        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = RecentDocumentsMenu.shared
        recent.submenu = recentMenu

        main.addSubmenu("File", [
            item("Open…", #selector(AppDelegate.openDocument(_:)), "o"),
            recent,
            .separator(),
            item("Edit in Text Editor", #selector(DocumentWindowController.editInTextEditor(_:)), "e"),
            item("Show in Finder", #selector(DocumentWindowController.showInFinder(_:)), "r", [.command, .shift]),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Print…", #selector(DocumentWindowController.printDocument(_:)), "p"),
        ])

        main.addSubmenu("Edit", [
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(DocumentWindowController.showFind(_:)), "f"),
            item("Find Next", #selector(DocumentWindowController.findNextMatch(_:)), "g"),
            item("Find Previous", #selector(DocumentWindowController.findPreviousMatch(_:)), "g", [.command, .shift]),
        ])

        main.addSubmenu("View", [
            item("Actual Size", #selector(DocumentWindowController.actualSize(_:)), "0"),
            item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "="),
            item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-"),
            .separator(),
            item("Reload", #selector(DocumentWindowController.reloadDocument(_:)), "r"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        let window = main.addSubmenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window
        return main
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        addItem(holder)
        return submenu
    }
}

final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for url in urls {
            let entry = NSMenuItem(title: url.lastPathComponent, action: #selector(AppDelegate.openRecent(_:)), keyEquivalent: "")
            entry.representedObject = url
            entry.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = NSDocumentController.shared
        clear.isEnabled = !urls.isEmpty
        menu.addItem(clear)
    }
}
