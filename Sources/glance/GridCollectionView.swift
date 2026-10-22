import AppKit

/// ↑/↓ are NSCollectionView's own selection movement; ←/→ step through the flat order (crossing
/// month sections); this adds open/exit/edit keys and single-click-to-open, with ⌘- and ⇧-click
/// selecting several tiles instead.
final class GridCollectionView: NSCollectionView {
    var onActivate: ((IndexPath) -> Void)?
    var onStep: ((Int) -> Void)?
    var onExit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch GridKey.from(event) {
        case .activate: if let path = selectionIndexPaths.first { onActivate?(path) }
        case .exit: onExit?()
        case .toggleFullScreen: window?.toggleFullScreen(nil)
        case .editInExcerpt: _ = window?.tryToPerform(#selector(BrowserWindowController.editInExcerpt(_:)), with: nil)
        case .arrow(.left): onStep?(-1)
        case .arrow(.right): onStep?(1)
        case .arrow(.up), .arrow(.down), nil: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let extending = !event.modifierFlags.intersection([.command, .shift]).isEmpty
        if !extending, let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            onActivate?(path)
        } else {
            super.mouseDown(with: event)
        }
    }
}
