import CoreGraphics

public enum ViewerTitle {
    /// `a.jpg — 12 / 340 — 4032×3024`; the size part is omitted until it is known.
    public static func text(fileName: String, index: Int, count: Int, pixelSize: CGSize?) -> String {
        var parts = [fileName, "\(index + 1) / \(count)"]
        if let size = pixelSize { parts.append("\(Int(size.width))×\(Int(size.height))") }
        return parts.joined(separator: " — ")
    }
}
