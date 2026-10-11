import AppKit
import GlanceCore

/// One window per folder. Owns the folder model, its watcher and the prefetch cache, and swaps
/// between the viewer and the grid (both stay alive, so the grid keeps its scroll position).
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let model: FolderModel
    var onClose: (() -> Void)?

    private let decodeCache: DecodeCache
    private let viewer: ViewerView
    private let grid: GridViewController
    private var watcher: FolderWatcher?
    private var showingGrid = false
    private var resolutionGeneration = 0
    private var scanGeneration = 0
    private var scanned = false

    init(model: FolderModel, thumbnails: ThumbnailService, startInGrid: Bool) {
        // Locals, not self.viewer/self.grid: self can't be read before super.init.
        let viewer = ViewerView()
        let grid = GridViewController(model: model, thumbnails: thumbnails)
        self.model = model
        self.viewer = viewer
        self.grid = grid
        decodeCache = DecodeCache(decoder: ImageDecoder(), maxPixelSize: Self.screenPixels())

        let window = NSWindow(contentRect: Self.initialFrame(), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 320, height: 240)
        window.setFrameAutosaveName("glance.browser")
        let container = NSView()
        for child in [viewer, grid.view] {
            child.frame = container.bounds
            child.autoresizingMask = [.width, .height]
            container.addSubview(child)
        }
        window.contentView = container
        super.init(window: window)
        window.delegate = self

        viewer.onCommand = { [weak self] in self?.handle($0) }
        viewer.onNeedsResolution = { [weak self] url, pixels in self?.decodeHigherResolution(url, pixels) }
        grid.onOpen = { [weak self] index in
            self?.model.select(index)
            self?.showViewer()
        }
        grid.onExit = { [weak self] in self?.showViewer() }
        decodeCache.onDecoded = { [weak self] url, result in
            guard let self, url == self.model.current else { return }
            self.viewer.show(result, for: url)
            self.updateTitle()
        }
        model.onChange = { [weak self] in self?.modelChanged($0) }
        watcher = FolderWatcher(folder: model.folder) { [weak self] in self?.rescan() }

        modelChanged(.files)
        startInGrid ? showGrid() : showViewer()
        rescan()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func screenPixels() -> Int {
        let longest = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 2880
        return Int(longest.rounded(.up))
    }

    private static func initialFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: visible.width * 0.7, height: visible.height * 0.7)
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Modes

    func showViewer() {
        showingGrid = false
        grid.view.isHidden = true
        viewer.isHidden = false
        window?.makeFirstResponder(viewer)
    }

    func showGrid() {
        showingGrid = true
        viewer.isHidden = true
        grid.view.isHidden = false
        grid.reveal(model.currentIndex)
        window?.makeFirstResponder(grid.firstResponderView)
    }

    @objc func toggleGrid(_ sender: Any?) { showingGrid ? showViewer() : showGrid() }

    // MARK: Model

    /// Lists the folder off the main thread (a network volume can take seconds), then hands the
    /// result to the model. The first scan keeps the file the window was opened on, even if it
    /// is not an image; a newer scan supersedes an older one still in flight.
    private func rescan() {
        scanGeneration += 1
        let generation = scanGeneration
        let folder = model.folder
        let keep = scanned ? nil : model.current
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = try? FolderModel.listing(folder, including: keep)
            DispatchQueue.main.async {
                guard let self, generation == self.scanGeneration else { return }
                let wasScanned = self.scanned
                self.scanned = true
                if let files { self.model.replaceFiles(files) }
                if !wasScanned, self.model.files.isEmpty { self.modelChanged(.files) }
                self.decodeCache.revalidate()
            }
        }
    }

    private func modelChanged(_ change: FolderModel.Change) {
        if change == .files { grid.reload() }
        guard let index = model.currentIndex, let url = model.current else {
            decodeCache.clear()
            scanned ? viewer.showEmpty() : viewer.showLoading()
            updateTitle()
            return
        }
        decodeCache.focus(on: index, in: model.files)
        // Only a change of file re-shows; a list change around the same file keeps its zoom.
        if url != viewer.shownURL, let ready = decodeCache.result(for: url) { viewer.show(ready, for: url) }
        updateTitle()
    }

    private func updateTitle() {
        guard let window else { return }
        guard let index = model.currentIndex, let url = model.current else {
            window.title = model.folder.lastPathComponent
            window.representedURL = model.folder
            return
        }
        // From the cache, not the viewer: while the new image decodes, the viewer still shows the old one.
        let size = (try? decodeCache.result(for: url)?.get())?.pixelSize
        window.title = ViewerTitle.text(fileName: url.lastPathComponent, index: index, count: model.files.count, pixelSize: size)
        window.representedURL = url
    }

    private func handle(_ command: ViewerCommand) {
        switch command {
        case .next: model.move(by: 1)
        case .previous: model.move(by: -1)
        case .first: model.moveToFirst()
        case .last: model.moveToLast()
        case .toggleGrid: toggleGrid(nil)
        case .toggleFullScreen: window?.toggleFullScreen(nil)
        case .exitFullScreen: if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        }
    }

    private func decodeHigherResolution(_ url: URL, _ pixels: Int) {
        resolutionGeneration += 1
        let generation = resolutionGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ImageDecoder().decode(url, maxPixelSize: pixels)
            DispatchQueue.main.async {
                guard let self, self.resolutionGeneration == generation, case .success(let image) = result else { return }
                self.viewer.upgrade(image)
            }
        }
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}
