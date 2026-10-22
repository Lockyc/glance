import AppKit
import GlanceCore

enum ViewerCommand { case next, previous, up, down, first, last, toggleGrid, toggleFullScreen, exitFullScreen, editInExcerpt }

/// One image on a CALayer: fit / zoom / pan, animation, and in-place messages for failures and
/// empty folders. Holds no navigation state — commands go up through `onCommand`.
final class ViewerView: NSView, ZoomActions {
    var onCommand: ((ViewerCommand) -> Void)?
    /// Asked when the zoom shows more detail than the current bitmap holds (url, long-side px).
    var onNeedsResolution: ((URL, Int) -> Void)?

    private let imageLayer = CALayer()
    private let message = NSTextField(labelWithString: "")
    private var image: DecodedImage?
    /// The file on screen, image or message — `nil` for the empty and loading states.
    private(set) var shownURL: URL?
    private(set) var viewport: Viewport?
    private var shownPixels = 0
    private var requestedPixels = 0
    private var animationGeneration = 0
    private var resolutionWork: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 15)
        message.isHidden = true
        message.translatesAutoresizingMaskIntoConstraints = false
        addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: centerXAnchor),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    // MARK: Content

    func show(_ result: Result<DecodedImage, DecodeError>, for url: URL) {
        stopAnimation()
        resolutionWork?.cancel()
        switch result {
        case .success(let decoded):
            image = decoded
            shownPixels = max(decoded.cgImage.width, decoded.cgImage.height)
            requestedPixels = shownPixels
            message.isHidden = true
            imageLayer.isHidden = false
            imageLayer.contents = decoded.cgImage
            viewport = .fit(imageSize: decoded.pixelSize, viewSize: bounds.size, backingScale: backingScale)
            applyViewport()
            if decoded.isAnimated { startAnimation(decoded.url) }
        case .failure:
            showMessage("Can't open \(url.lastPathComponent)")
        }
        shownURL = url
    }

    func showEmpty() { showMessage("No images in this folder") }

    /// Blank until the folder listing arrives, so an unscanned folder never claims to be empty.
    func showLoading() { showMessage("") }

    func upgrade(_ decoded: DecodedImage) {
        guard decoded.url == image?.url, max(decoded.cgImage.width, decoded.cgImage.height) > shownPixels else { return }
        shownPixels = max(decoded.cgImage.width, decoded.cgImage.height)
        imageLayer.contents = decoded.cgImage
    }

    private func showMessage(_ text: String) {
        stopAnimation()
        resolutionWork?.cancel()
        image = nil
        shownURL = nil
        viewport = nil
        imageLayer.contents = nil
        imageLayer.isHidden = true
        message.stringValue = text
        message.isHidden = false
    }

    private func applyViewport() {
        guard let viewport, let image else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = viewport.imageFrame
        imageLayer.magnificationFilter = viewport.scale >= 2 ? .nearest : .linear
        CATransaction.commit()

        let needed = viewport.detailPixels(isVector: image.isVector)
        guard !image.isAnimated, needed > requestedPixels + requestedPixels / 20 else { return }
        requestedPixels = needed
        resolutionWork?.cancel()
        let url = image.url
        let work = DispatchWorkItem { [weak self] in self?.onNeedsResolution?(url, needed) }
        resolutionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    override func layout() {
        super.layout()
        if let viewport { self.viewport = viewport.resized(to: bounds.size, backingScale: backingScale) }
        applyViewport()
    }

    // MARK: Animation

    private func startAnimation(_ url: URL) {
        animationGeneration += 1
        let generation = animationGeneration
        CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] _, frame, stop in
            guard let self, self.animationGeneration == generation else { stop.pointee = true; return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.imageLayer.contents = frame
            CATransaction.commit()
        }
    }

    private func stopAnimation() { animationGeneration += 1 }

    // MARK: Zoom

    private var centrePoint: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func zoom(by factor: CGFloat, about point: CGPoint) {
        guard let viewport else { return }
        self.viewport = viewport.zoomed(by: factor, about: point)
        applyViewport()
    }

    @objc func zoomIn(_ sender: Any?) { zoom(by: 1.25, about: centrePoint) }
    @objc func zoomOut(_ sender: Any?) { zoom(by: 0.8, about: centrePoint) }

    @objc func actualSize(_ sender: Any?) {
        guard let viewport else { return }
        self.viewport = viewport.zoomed(to: 1, about: centrePoint)
        applyViewport()
    }

    @objc func zoomToFit(_ sender: Any?) {
        guard let viewport else { return }
        self.viewport = viewport.fitted()
        applyViewport()
    }

    // MARK: Input

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?: onCommand?(.previous)
        case .rightArrow?: onCommand?(.next)
        case .upArrow?: onCommand?(.up)
        case .downArrow?: onCommand?(.down)
        case .home?: onCommand?(.first)
        case .end?: onCommand?(.last)
        default:
            if event.keyCode == 53 { onCommand?(.exitFullScreen); return }
            switch event.charactersIgnoringModifiers {
            case "g", " ": onCommand?(.toggleGrid)
            case "f": onCommand?(.toggleFullScreen)
            case "e": onCommand?(.editInExcerpt)
            case "0": zoomToFit(nil)
            case "1": actualSize(nil)
            case "+", "=": zoomIn(nil)
            case "-": zoomOut(nil)
            default: super.keyDown(with: event)
            }
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, about: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            zoom(by: exp(event.scrollingDeltaY * 0.01), about: convert(event.locationInWindow, from: nil))
        } else if let viewport, !viewport.isFit {
            self.viewport = viewport.panned(by: CGSize(width: event.scrollingDeltaX, height: -event.scrollingDeltaY))
            applyViewport()
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// Whether the current click sequence started on this view. Opening from a grid tile happens
    /// on the first click, so the second click of that double-click must not toggle zoom here.
    private var clickSequenceIsOurs = false

    override func viewDidUnhide() {
        super.viewDidUnhide()
        clickSequenceIsOurs = false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount <= 1 { clickSequenceIsOurs = true }
        guard event.clickCount == 2, clickSequenceIsOurs, let viewport else { return }
        let point = convert(event.locationInWindow, from: nil)
        self.viewport = viewport.isFit ? viewport.zoomed(to: 1, about: point) : viewport.fitted()
        applyViewport()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewport else { return }
        self.viewport = viewport.panned(by: CGSize(width: event.deltaX, height: -event.deltaY))
        applyViewport()
    }
}
