import AppKit
import GlanceCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var controllers: [BrowserWindowController] = []
    private let thumbnails = ThumbnailService()
    private let roots: SubfolderRoots
    private var settingsWindow: NSWindow?

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

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: roots)))
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func makeDefaultViewer(_ sender: Any?) {
        DefaultHandler.claimAll(appURL: Bundle.main.bundleURL) { claimed, failed in
            let alert = NSAlert()
            alert.messageText = "glance now opens \(claimed) image types"
            if !failed.isEmpty { alert.informativeText = "Not claimed: " + failed.map(\.identifier).joined(separator: ", ") }
            alert.runModal()
        }
    }

    /// Always a new window on exactly `files`, in order; never reused by a later open.
    func openSet(_ files: [URL]) { openFixed(files, comparison: nil) }

    /// Always a new window, opening in the comparison grid; never reused by a later open.
    func openComparison(_ comparison: Comparison) { openFixed(comparison.files, comparison: comparison) }

    private func openFixed(_ files: [URL], comparison: Comparison?) {
        guard let first = files.first else { return }
        let model = FolderModel(folder: first.deletingLastPathComponent(), files: files.map(FolderModel.canonical),
                                current: nil, scope: .fixed)
        present(BrowserWindowController(model: model, thumbnails: thumbnails, startInGrid: comparison != nil, roots: roots,
                                        comparison: comparison))
    }

    private func present(_ controller: BrowserWindowController) {
        controller.onClose = { [weak self, weak controller] in self?.controllers.removeAll { $0 === controller } }
        controllers.append(controller)
        controller.showWindow(nil)
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

        if let existing = controllers.first(where: { $0.model.scope != .fixed && $0.model.folder.path == folder.path }) {
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
        present(BrowserWindowController(model: model, thumbnails: thumbnails, startInGrid: isFolder, roots: roots, landing: landing))
    }
}
