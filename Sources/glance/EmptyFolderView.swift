import AppKit

/// A scanned folder with no images, over viewer and grid alike: names the folder's subfolders and,
/// for a folder browsed on its own, offers Include Subfolders.
final class EmptyFolderView: NSView {
    var onInclude: (() -> Void)?

    private static let shownNames = 8

    private let title = NSTextField(labelWithString: "No images in this folder")
    private let subfolders = NSTextField(wrappingLabelWithString: "")
    private let include = NSButton(title: "Include Subfolders", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.textColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: 15)
        subfolders.textColor = .tertiaryLabelColor
        subfolders.alignment = .center
        subfolders.preferredMaxLayoutWidth = 480
        include.target = self
        include.action = #selector(includeClicked)
        let stack = NSStackView(views: [title, subfolders, include])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks pass through everywhere but the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === include ? hit : nil
    }

    /// `names`: the folder's subfolders; `includable`: whether Include Subfolders is off and can be turned on.
    func update(subfolders names: [String], includable: Bool) {
        let shown = names.prefix(Self.shownNames).joined(separator: ", ")
        let more = names.count > Self.shownNames ? " and \(names.count - Self.shownNames) more" : ""
        subfolders.stringValue = "Subfolders: \(shown)\(more)"
        subfolders.isHidden = names.isEmpty
        include.isHidden = names.isEmpty || !includable
    }

    @objc private func includeClicked() { onInclude?() }
}
