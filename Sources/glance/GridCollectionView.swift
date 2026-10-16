import AppKit

/// ↑/↓ are NSCollectionView's own selection movement; ←/→ step through the flat order (crossing
/// month sections); this adds open/exit keys and single-click-to-open.
final class GridCollectionView: NSCollectionView {
    var onActivate: ((IndexPath) -> Void)?
    var onStep: ((Int) -> Void)?
    var onExit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]).isEmpty
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            if let path = selectionIndexPaths.first { onActivate?(path) }
        case 53: // Esc
            onExit?()
        case 123 where bare: // ←
            onStep?(-1)
        case 124 where bare: // →
            onStep?(1)
        default:
            if bare, event.charactersIgnoringModifiers == "g" || event.charactersIgnoringModifiers == " " {
                onExit?()
            } else if bare, event.charactersIgnoringModifiers == "f" {
                window?.toggleFullScreen(nil)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            onActivate?(path)
        } else {
            super.mouseDown(with: event)
        }
    }
}
