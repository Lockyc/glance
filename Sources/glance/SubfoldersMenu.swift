import AppKit

/// View → Subfolders: the key window's root's top-level folders, checked when included. Stays in
/// the menu when the window is not a root, with one disabled line saying how to turn it on.
final class SubfoldersMenu: NSObject, NSMenuDelegate {
    static let shared = SubfoldersMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu, for: NSApp.keyWindow?.windowController as? BrowserWindowController)
    }

    func populate(_ menu: NSMenu, for controller: BrowserWindowController?) {
        menu.removeAllItems()
        guard let controller, controller.isRoot else {
            menu.addItem(disabled("Turn on Include Subfolders to choose folders"))
            return
        }
        let names = controller.subfolders()
        if names.isEmpty { menu.addItem(disabled("No subfolders")) }
        for name in names {
            let item = NSMenuItem(title: name, action: #selector(BrowserWindowController.toggleExcludedSubfolder(_:)), keyEquivalent: "")
            item.representedObject = name
            menu.addItem(item)
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
