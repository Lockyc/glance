import AppKit

/// The grid half of a browser window: the thumbnail grid of a folder or set, or a comparison's
/// variant × shot grid. Indices are the window model's file indices.
protocol BrowserGrid: AnyObject {
    var view: NSView { get }
    var firstResponderView: NSView { get }
    var onOpen: ((Int) -> Void)? { get set }
    var onExit: (() -> Void)? { get set }
    func reload()
    func reveal(_ index: Int?)
}
