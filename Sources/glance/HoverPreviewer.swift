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
    private var request: ThumbnailRequest?
    /// The target the preview was shown for, while it is.
    private var shown: HoverTarget?

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
        shown = nil
        preview.hide()
    }

    /// Re-reads the open preview's file, for a file that may have been re-saved: the image swaps
    /// in place and the preview re-shapes around it. An unchanged file is a cache hit.
    func refresh() {
        guard let target = shown, !preview.isHidden else { return }
        let key = hoveredKey
        request?.cancel()
        request = thumbnails.request(target.url, pixelSize: target.pixels) { [weak self] result in
            guard let self, self.hoveredKey == key, case .success(let image) = result else { return }
            self.preview.update(image, frame: self.frame(for: image, target))
        }
    }

    /// Shows the tile's thumbnail at once and sharpens it when the larger decode lands; with no
    /// thumbnail yet, waits for that decode, so a failed one never leaves an empty box.
    private func show(_ target: HoverTarget, key: AnyHashable?) {
        shown = target
        if let image = target.image { present(image, target) }
        request = thumbnails.request(target.url, pixelSize: target.pixels) { [weak self] result in
            guard let self, self.hoveredKey == key, case .success(let image) = result else { return }
            self.preview.isHidden ? self.present(image, target) : self.preview.update(image)
        }
    }

    private func present(_ image: CGImage, _ target: HoverTarget) {
        preview.show(image, frame: frame(for: image, target))
    }

    private func frame(for image: CGImage, _ target: HoverTarget) -> CGRect {
        HoverPreview.frame(around: target.tile, imageSize: CGSize(width: image.width, height: image.height), side: target.side, bounds: target.bounds)
    }
}
