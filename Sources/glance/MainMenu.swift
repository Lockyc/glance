import AppKit
import Sparkle

enum MainMenu {
    static func make(updater: SPUStandardUpdaterController?) -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: "glance")
        app.addItem(withTitle: "About glance", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        // Shown without an updater too (`swift run`), just inert, so the menu reads the same everywhere.
        let check = app.addItem(withTitle: "Check for Updates…",
                                action: updater.map { _ in #selector(SPUStandardUpdaterController.checkForUpdates(_:)) },
                                keyEquivalent: "")
        check.target = updater
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Make Default Image Viewer", action: #selector(AppDelegate.makeDefaultViewer(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide glance", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(in: main, title: "File")
        file.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        file.addItem(.separator())
        imageItems().forEach(file.addItem)
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = submenu(in: main, title: "Edit")
        edit.addItem(copyItem())

        let view = submenu(in: main, title: "View")
        view.addItem(withTitle: "Toggle Grid", action: #selector(BrowserWindowController.toggleGrid(_:)), keyEquivalent: "g")
        view.addItem(withTitle: "Show Comparison Context", action: #selector(BrowserWindowController.toggleComparisonContext(_:)),
                     keyEquivalent: "")
        view.addItem(.separator())
        view.addItem(withTitle: "Include Subfolders", action: #selector(BrowserWindowController.toggleSubfolders(_:)), keyEquivalent: "")
        let subfolders = view.addItem(withTitle: "Subfolders", action: nil, keyEquivalent: "")
        let subfoldersMenu = NSMenu(title: "Subfolders")
        subfoldersMenu.delegate = SubfoldersMenu.shared
        subfolders.submenu = subfoldersMenu
        view.addItem(.separator())
        view.addItem(withTitle: "Zoom In", action: #selector(ZoomActions.zoomIn(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "Zoom Out", action: #selector(ZoomActions.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Actual Size", action: #selector(ZoomActions.actualSize(_:)), keyEquivalent: "1")
        view.addItem(withTitle: "Zoom to Fit", action: #selector(ZoomActions.zoomToFit(_:)), keyEquivalent: "0")
        view.addItem(.separator())
        let fullScreen = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        let window = submenu(in: main, title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = window

        return main
    }

    /// The commands on the image in view or the grid's selection: the File menu's middle group and the right-click menu.
    static func imageItems() -> [NSMenuItem] {
        let upArrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        return [
            NSMenuItem(title: "Browse Folder", action: #selector(BrowserWindowController.browseFolder(_:)), keyEquivalent: upArrow),
            NSMenuItem(title: "Show in Finder", action: #selector(BrowserWindowController.showInFinder(_:)), keyEquivalent: "r"),
            NSMenuItem(title: "Edit in Excerpt", action: #selector(BrowserWindowController.editInExcerpt(_:)), keyEquivalent: "e"),
        ]
    }

    /// Edit → Copy, or ⌘C: the image in view or the grid's selection.
    static func copyItem() -> NSMenuItem {
        NSMenuItem(title: "Copy", action: #selector(BrowserWindowController.copy(_:)), keyEquivalent: "c")
    }

    /// The right-click menu of the viewer, grid tiles and comparison cells.
    static func contextMenu() -> NSMenu {
        let menu = NSMenu()
        imageItems().forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(copyItem())
        return menu
    }

    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem()
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }
}
