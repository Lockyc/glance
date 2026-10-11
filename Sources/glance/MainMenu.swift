import AppKit

enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: "glance")
        app.addItem(withTitle: "About glance", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Make Default Image Viewer", action: #selector(AppDelegate.makeDefaultViewer(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide glance", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(in: main, title: "File")
        file.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let view = submenu(in: main, title: "View")
        view.addItem(withTitle: "Toggle Grid", action: #selector(BrowserWindowController.toggleGrid(_:)), keyEquivalent: "g")
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

    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem()
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }
}
