import AppKit

/// The sticky month title above a run of grid tiles.
final class MonthHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("MonthHeader")
    static let height: CGFloat = 30

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.94).cgColor
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: 16, y: (bounds.height - height) / 2, width: bounds.width - 32, height: height)
    }

    func configure(_ title: String?) { label.stringValue = title ?? "" }
}
