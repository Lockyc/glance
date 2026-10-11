import AppKit

/// The enlarged hover preview. Sits above the grid's scroll view and ignores the mouse, so the
/// grid never reflows and the tile underneath still receives clicks.
final class HoverPreviewView: NSView {
    private let imageLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.cornerRadius = 6
        imageLayer.masksToBounds = true
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ image: CGImage?, frame: CGRect) {
        self.frame = frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.contents = image
        CATransaction.commit()
        alphaValue = 0
        isHidden = false
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }
    }

    func update(_ image: CGImage) { imageLayer.contents = image }

    func hide() {
        isHidden = true
        imageLayer.contents = nil
    }
}
