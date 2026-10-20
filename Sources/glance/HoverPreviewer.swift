import AppKit
import GlanceCore

/// What a grid hands the previewer when the hover delay elapses; all geometry is in the
/// previewer's host-view coordinates.
struct HoverTarget {
    let url: URL
    let tile: CGRect
    let image: CGImage?
    let side: CGFloat
    let bounds: CGRect
    let pixels: Int
}

/// The delayed, enlarged hover preview shared by the thumbnail and comparison grids.
final class HoverPreviewer {
    private let preview: HoverPreviewView
    private let thumbnails: ThumbnailService
    private var timer: Timer?
    private var hoveredKey: AnyHashable?
    private var request: Operation?

    init(preview: HoverPreviewView, thumbnails: ThumbnailService) {
        self.preview = preview
        self.thumbnails = thumbnails
    }

    /// Re-arms the `HoverPreview.delay` timer when `key` changes; `resolve` is asked when it fires.
    func hover(over key: AnyHashable?, resolve: @escaping () -> HoverTarget?) {
        guard key != hoveredKey else { return }
        hide()
        hoveredKey = key
        guard key != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: HoverPreview.delay, repeats: false) { [weak self] _ in
            guard let self, let target = resolve() else { return }
            self.show(target, key: key)
        }
    }

    /// Also clears the hovered key, so after a scroll the next mouse move re-arms the preview.
    func hide() {
        timer?.invalidate()
        timer = nil
        request?.cancel()
        request = nil
        hoveredKey = nil
        preview.hide()
    }

    private func show(_ target: HoverTarget, key: AnyHashable?) {
        let aspectSource = target.image.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 1, height: 1)
        preview.show(target.image, frame: HoverPreview.frame(around: target.tile, imageSize: aspectSource, side: target.side, bounds: target.bounds))
        request = thumbnails.request(target.url, pixelSize: target.pixels) { [weak self] result in
            guard let self, self.hoveredKey == key, case .success(let image) = result else { return }
            self.preview.update(image)
        }
    }
}
