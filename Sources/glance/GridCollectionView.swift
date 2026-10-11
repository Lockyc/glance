import AppKit

/// Arrow keys are NSCollectionView's own selection movement; this adds open/exit keys and
/// single-click-to-open.
final class GridCollectionView: NSCollectionView {
    var onActivate: ((Int) -> Void)?
    var onExit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]).isEmpty
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            if let index = selectionIndexPaths.first?.item { onActivate?(index) }
        case 53: // Esc
            onExit?()
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
        if let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item {
            onActivate?(index)
        } else {
            super.mouseDown(with: event)
        }
    }
}
