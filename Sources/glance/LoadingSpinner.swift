import AppKit

extension NSProgressIndicator {
    /// The small spinner a grid cell shows until its thumbnail arrives; invisible when stopped.
    static func thumbnailSpinner() -> NSProgressIndicator {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.sizeToFit()
        return spinner
    }

    /// Centres the spinner in `rect` (its superview's coordinates).
    func center(in rect: CGRect) {
        setFrameOrigin(NSPoint(x: rect.midX - frame.width / 2, y: rect.midY - frame.height / 2))
    }
}
