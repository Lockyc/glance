import AppKit
import GlanceCore

final class GridViewController: NSViewController {
    var onOpen: ((Int) -> Void)?
    var onExit: (() -> Void)?
    private let model: FolderModel

    init(model: FolderModel, thumbnails: ThumbnailService) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() { view = NSView() }
    var firstResponderView: NSView { view }
    func reload() {}
    func reveal(_ index: Int?) {}
}
