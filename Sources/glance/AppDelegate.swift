import AppKit
import GlanceCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var controllers: [BrowserWindowController] = []
    private let thumbnails = ThumbnailService()
    private let roots: SubfolderRoots

    init(roots: SubfolderRoots = .shared) {
        self.roots = roots
        super.init()
    }

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

    /// A file opens its folder at that file; a folder opens in the grid. Anything inside a root
    /// opens the root's window — a folder there lands on its newest image. A folder that already
    /// has a window reuses it.
    func openURL(_ url: URL) {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let opened = (isFolder ? url : url.deletingLastPathComponent()).resolvingSymlinksInPath()
        let root = roots.root(covering: isFolder ? opened : FolderModel.canonical(url))
        let folder = root?.url.resolvingSymlinksInPath() ?? opened
        let file = isFolder ? nil : url
        let landing = isFolder && root != nil ? opened : nil

        if let existing = controllers.first(where: { $0.model.folder.path == folder.path }) {
            if let file { existing.model.select(file) }
            if let landing { existing.land(at: landing) }
            isFolder ? existing.showGrid() : existing.showViewer()
            existing.showWindow(nil)
            return
        }

        // Opens on the one file at once; the window lists the folder in the background.
        // A tree's files and dates stay parallel even before the first listing arrives.
        let scope: FolderModel.Scope = root.map { .tree(excluded: Set($0.excluded)) } ?? .flat
        let seeded = file.map { [FolderModel.canonical($0)] } ?? []
        let model = FolderModel(folder: folder, files: seeded, current: file, scope: scope,
                                dates: scope == .flat ? [] : seeded.map { _ in .distantPast })
        let controller = BrowserWindowController(model: model, thumbnails: thumbnails, startInGrid: isFolder,
                                                 roots: roots, landing: landing)
        controller.onClose = { [weak self, weak controller] in self?.controllers.removeAll { $0 === controller } }
        controllers.append(controller)
        controller.showWindow(nil)
    }
}
