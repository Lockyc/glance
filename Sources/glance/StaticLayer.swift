import AppKit

/// TV static: what a grid cell shows until its thumbnail arrives. Hidden until `isAnimating`.
/// Every cell cycles the same few noise frames on the render server, each from its own start, so
/// a screenful of loading cells costs no CPU and doesn't flicker in step. Reduce Motion holds one frame.
final class StaticLayer: CALayer {
    private static let side = 192
    private static let frames: [CGImage] = (0..<6).compactMap { _ in noise() }
    private static let cycle: CFTimeInterval = 0.3

    var isAnimating = false {
        didSet {
            guard isAnimating != oldValue else { return }
            isHidden = !isAnimating
            removeAllAnimations()
            guard isAnimating else { return }
            contents = Self.frames.randomElement()
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = Self.frames
            animation.calculationMode = .discrete
            animation.duration = Self.cycle
            animation.repeatCount = .infinity
            animation.timeOffset = .random(in: 0..<Self.cycle)
            add(animation, forKey: "static")
        }
    }

    override init() {
        super.init()
        isHidden = true
        contentsGravity = .resizeAspectFill
        magnificationFilter = .nearest
        masksToBounds = true
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Dim grey grain, so it reads as loading without outshining the images around it.
    private static func noise() -> CGImage? {
        var pixels = (0..<(side * side)).map { _ in UInt8.random(in: 14...80) }
        return pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
    }
}
