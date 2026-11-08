import AppKit

/// The grid half of a browser window: the thumbnail grid of a folder or set, or a comparison's
/// variant × shot grid. Indices are the window model's file indices.
protocol BrowserGrid: AnyObject {
    var view: NSView { get }
    var firstResponderView: NSView { get }
    var onOpen: ((Int) -> Void)? { get set }
    var onExit: (() -> Void)? { get set }
    /// The selected files, in grid order: what Edit in Excerpt sends.
    var selectedFiles: [URL] { get }
    func reload()
    /// Re-reads the thumbnails and hover preview on screen in place, for files that may have been re-saved.
    func refreshThumbnails()
    func reveal(_ index: Int?)
    /// Drops the hover preview and any pending one, so leaving the grid never strands either.
    func hidePreview()
}
