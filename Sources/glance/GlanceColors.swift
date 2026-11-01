import AppKit

extension NSColor {
    /// The window's dark backdrop, shared by the viewer, the grid and the comparison grid, which
    /// swap in place in one window — so a copy retuned alone shows as a tone jump on G.
    static let glanceBackground = NSColor(white: 0.08, alpha: 1)
}
