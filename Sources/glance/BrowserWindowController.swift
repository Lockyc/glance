import AppKit
import GlanceCore

/// One window per folder, set or comparison. Owns the folder model, its watcher and the prefetch cache, and swaps
/// between the viewer and the grid (both stay alive, so the grid keeps its scroll position).
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let model: FolderModel
    var onClose: (() -> Void)?

    /// Where Edit in Excerpt sends images; tests swap it for a recorder.
    struct Excerpt {
        var installed: () -> Bool
        var open: ([URL]) -> Void

        /// The installed Excerpt, handed every image in one open so it takes them as one series.
        static let system = Excerpt(
            installed: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: ExternalEditor.excerptBundleIdentifier) != nil },
            open: { urls in
                guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ExternalEditor.excerptBundleIdentifier)
                else { return }
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            })
    }
    var excerpt = Excerpt.system

    private let decodeCache: DecodeCache
    private let viewer: ViewerView
    private let grid: any BrowserGrid
    /// Set for a comparison window: the grid is the variant × shot grid and the viewer steps in 2D.
    private let comparison: Comparison?
    /// A comparison's strip and map over the viewer; nil for any other window.
    private(set) var context: ComparisonContextView?
    private(set) var showingGrid = false
    /// Full-detail re-decodes for zoom run one at a time; a newer request or a change of file cancels the last.
    private let upgrades: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var upgrade: Operation?
    private let roots: SubfolderRoots
    /// A folder opened (not a file) inside a root: the first listing lands on its newest image.
    private let landing: URL?
    private var watcher: TreeWatcher?
    /// Bumped on a scope change so a listing of the old scope is dropped when it returns.
    private var scanGeneration = 0
    private var scanned = false
    private var scanning = false
    private var pendingChange: TreeWatcher.Change?
    /// The root's top-level folders, read by the scan so View → Subfolders never touches the disk.
    private var rootFolders: [String] = []

    init(model: FolderModel, thumbnails: ThumbnailService, startInGrid: Bool, roots: SubfolderRoots = .shared, landing: URL? = nil,
         comparison: Comparison? = nil) {
        // Locals, not self.viewer/self.grid: self can't be read before super.init.
        let viewer = ViewerView()
        let grid: any BrowserGrid = comparison.map { ComparisonGridViewController(comparison: $0, thumbnails: thumbnails) }
            ?? GridViewController(model: model, thumbnails: thumbnails)
        self.model = model
        self.comparison = comparison
        self.roots = roots
        self.landing = landing
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
        if let comparison {
            let context = ComparisonContextView(comparison: comparison, thumbnails: thumbnails)
            context.frame = container.bounds
            context.autoresizingMask = [.width, .height]
            context.isHidden = true // until showViewer, so a window that opens on the grid requests no strip thumbnails
            container.addSubview(context, positioned: .above, relativeTo: viewer)
            self.context = context
        }
        window.contentView = container
        super.init(window: window)
        window.delegate = self

        context?.onSelect = { [weak self] cell in
            guard let self, let index = self.comparison?.cells.firstIndex(of: cell) else { return }
            self.model.select(index)
        }
        layoutViewer()
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
        watch()
        NotificationCenter.default.addObserver(self, selector: #selector(rootsChanged), name: SubfolderRoots.didChange, object: roots)

        // A fixed list is complete from the start, so an empty one reads as empty, not loading.
        if model.scope == .fixed { scanned = true }
        modelChanged(.files)
        startInGrid ? showGrid() : showViewer()
        if model.scope != .fixed { request(.everything) }
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
        context?.isHidden = false
        window?.makeFirstResponder(viewer)
    }

    func showGrid() {
        showingGrid = true
        viewer.isHidden = true
        context?.isHidden = true
        grid.view.isHidden = false
        grid.reveal(model.currentIndex)
        window?.makeFirstResponder(grid.firstResponderView)
    }

    @objc func toggleGrid(_ sender: Any?) { showingGrid ? showViewer() : showGrid() }

    /// The viewer leaves the bottom strip to a comparison's context.
    private func layoutViewer() {
        guard let container = window?.contentView else { return }
        let inset = context == nil ? 0 : ComparisonContextView.stripHeight
        viewer.frame = NSRect(x: 0, y: inset, width: container.bounds.width, height: container.bounds.height - inset)
    }

    // MARK: Model

    var isRoot: Bool {
        if case .tree = model.scope { return true }
        return false
    }

    private func watch() {
        guard model.scope != .fixed else { return }
        watcher = TreeWatcher(folder: model.folder, recursive: isRoot) { [weak self] in self?.request($0) }
    }

    private func request(_ change: TreeWatcher.Change) {
        pendingChange = pendingChange.map { $0.merged(with: change) } ?? change
        runScan()
    }

    /// One listing at a time, off the main thread (a network volume can take seconds); changes
    /// arriving meanwhile merge and run next. A tree re-reads only the changed folders once it
    /// has been walked. The first listing keeps the file the window was opened on, even if it is
    /// not an image.
    private func runScan() {
        guard !scanning, let change = pendingChange else { return }
        pendingChange = nil
        scanning = true
        let generation = scanGeneration
        let folder = model.folder, scope = model.scope, snapshot = model.listing
        let keep = scanned ? nil : model.current
        var dirs: Set<URL>?
        if scanned, case .directories(let changed) = change, case .tree = scope { dirs = changed }
        // The top-level folder set changes only with the root itself, so a pass that re-reads
        // deeper folders keeps the names it has.
        let readFolders = scope != .flat && (dirs?.contains { SubfolderRoots.relativePath(of: $0, in: folder) == "" } ?? true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let listing: FolderModel.Listing?
            if let dirs, case .tree(let excluded) = scope {
                listing = FolderModel.relist(snapshot, root: folder, excluded: excluded, changed: dirs)
            } else {
                listing = try? FolderModel.listing(folder, scope: scope, including: keep)
            }
            let folders = readFolders ? FolderModel.subfolders(of: folder) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                defer { self.runScan() }
                guard generation == self.scanGeneration else { return }
                let first = !self.scanned
                self.scanned = true
                if let folders { self.rootFolders = folders }
                if let listing { self.model.replaceFiles(listing.files, dates: listing.dates) }
                if first, let landing = self.landing { self.land(at: landing) }
                if first, self.model.files.isEmpty { self.modelChanged(.files) }
                self.decodeCache.revalidate()
            }
        }
    }

    /// Selects the newest image under `folder` (the list is oldest first).
    func land(at folder: URL) {
        let prefix = folder.path + "/"
        guard let index = model.files.lastIndex(where: { $0.path.hasPrefix(prefix) }) else { return }
        model.select(index)
        if showingGrid { grid.reveal(index) }
    }

    // MARK: Subfolders

    @objc func toggleSubfolders(_ sender: Any?) {
        isRoot ? roots.disable(model.folder) : roots.enable(model.folder)
    }

    @objc func toggleExcludedSubfolder(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, case .tree(let excluded) = model.scope else { return }
        roots.setExcluded(name, !excluded.contains(name), in: model.folder)
    }

    /// The root's top-level folders, for View → Subfolders, as the last scan found them.
    func subfolders() -> [String] { rootFolders }

    @objc private func rootsChanged() {
        guard model.scope != .fixed else { return }
        let scope: FolderModel.Scope = roots.root(at: model.folder).map { .tree(excluded: Set($0.excluded)) } ?? .flat
        guard scope != model.scope else { return }
        let wasRoot = isRoot
        model.setScope(scope)
        scanGeneration += 1
        if wasRoot != isRoot { watch() }
        request(.everything)
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
        context?.current = comparison?.cells[index]
        // Only a change of file re-shows; a list change around the same file keeps its zoom.
        if url != viewer.shownURL {
            upgrade?.cancel()
            if let ready = decodeCache.result(for: url) { viewer.show(ready, for: url) }
        }
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
        if let comparison {
            let cell = comparison.cells[index]
            window.title = ViewerTitle.comparison(variant: comparison.variants[cell.column].label, row: comparison.rowLabel(cell.row),
                                                  fileName: url.lastPathComponent, pixelSize: size)
        } else {
            window.title = ViewerTitle.text(fileName: url.lastPathComponent, index: index, count: model.files.count, pixelSize: size)
        }
        window.representedURL = url
    }

    private func handle(_ command: ViewerCommand) {
        let fullScreen = window?.styleMask.contains(.fullScreen) == true
        switch command {
        case .next: comparison == nil ? model.move(by: 1) : step(.right)
        case .previous: comparison == nil ? model.move(by: -1) : step(.left)
        case .up: step(.up)
        case .down: step(.down)
        case .first: model.moveToFirst()
        case .last: model.moveToLast()
        case .toggleGrid: toggleGrid(nil)
        case .toggleFullScreen: window?.toggleFullScreen(nil)
        case .editInExcerpt: editInExcerpt(nil)
        case .exitFullScreen:
            if fullScreen {
                window?.toggleFullScreen(nil)
            } else if comparison != nil {
                showGrid()
            }
        }
    }

    /// A comparison's 2D step from the current cell; without a comparison there is no up or down.
    private func step(_ move: Comparison.Move) {
        guard let comparison, let index = model.currentIndex,
              let target = comparison.viewerStep(from: comparison.cells[index], move),
              let next = comparison.cells.firstIndex(of: target) else { return }
        model.select(next)
    }

    private func decodeHigherResolution(_ url: URL, _ pixels: Int) {
        upgrade?.cancel()
        let op = BlockOperation()
        op.addExecutionBlock { [weak self, weak op] in
            guard let op, !op.isCancelled else { return }
            let result = ImageDecoder().decode(url, maxPixelSize: pixels)
            DispatchQueue.main.async {
                guard let self, !op.isCancelled, case .success(let image) = result else { return }
                self.viewer.upgrade(image)
            }
        }
        upgrade = op
        upgrades.addOperation(op)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

extension BrowserWindowController {
    /// The grid's selection while the grid shows, else the image in view.
    private var editTargets: [URL] { showingGrid ? grid.selectedFiles : model.current.map { [$0] } ?? [] }

    private var editRefusal: String? { ExternalEditor.refusal(for: editTargets, installed: excerpt.installed()) }

    /// File → Edit in Excerpt, or E: several images open there as one series.
    @objc func editInExcerpt(_ sender: Any?) {
        guard editRefusal == nil else {
            NSSound.beep()
            return
        }
        excerpt.open(editTargets)
    }
}

extension BrowserWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(editInExcerpt(_:)) {
            let refusal = editRefusal
            item.toolTip = refusal
            return refusal == nil
        }
        if model.scope == .fixed, item.action == #selector(toggleSubfolders(_:)) || item.action == #selector(toggleExcludedSubfolder(_:)) {
            return false
        }
        switch item.action {
        case #selector(toggleSubfolders(_:)):
            item.state = isRoot ? .on : .off
        case #selector(toggleExcludedSubfolder(_:)):
            if case .tree(let excluded) = model.scope, let name = item.representedObject as? String {
                item.state = excluded.contains(name) ? .off : .on
            }
        default:
            break
        }
        return true
    }
}
