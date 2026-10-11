import AppKit
import GlanceCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [BrowserWindowController] = []
    private let thumbnails = ThumbnailService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        NSApp.activate()
        // Files passed at launch arrive via application(_:open:) before this async block runs.
        DispatchQueue.main.async { if self.controllers.isEmpty { self.openDocument(nil) } }
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        urls.forEach(openURL)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            openURL(url)
        } else if controllers.isEmpty {
            NSApp.terminate(nil)
        }
    }

    @objc func makeDefaultViewer(_ sender: Any?) {
        DefaultHandler.claimAll(appURL: Bundle.main.bundleURL) { claimed, failed in
            let alert = NSAlert()
            alert.messageText = "glance now opens \(claimed) image types"
            if !failed.isEmpty { alert.informativeText = "Not claimed: " + failed.map(\.identifier).joined(separator: ", ") }
            alert.runModal()
        }
    }

    /// A file opens its folder at that file; a folder opens in the grid. A folder that already
    /// has a window reuses it.
    func openURL(_ url: URL) {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = (isFolder ? url : url.deletingLastPathComponent()).resolvingSymlinksInPath()
        let file = isFolder ? nil : url

        if let existing = controllers.first(where: { $0.model.folder == folder }) {
            if let file { existing.model.select(file) }
            isFolder ? existing.showGrid() : existing.showViewer()
            existing.showWindow(nil)
            return
        }

        // Opens on the one file at once; the window lists the folder in the background.
        let model = FolderModel(folder: folder, files: file.map { [FolderModel.canonical($0)] } ?? [], current: file)
        let controller = BrowserWindowController(model: model, thumbnails: thumbnails, startInGrid: isFolder)
        controller.onClose = { [weak self, weak controller] in self?.controllers.removeAll { $0 === controller } }
        controllers.append(controller)
        controller.showWindow(nil)
    }
}
