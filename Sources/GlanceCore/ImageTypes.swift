import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Which files glance opens: every image type ImageIO decodes, plus SVG (rendered by NSImage).
/// PDF is excluded everywhere — PDFs stay with Preview.
public enum ImageTypes {
    public static let supported: Set<UTType> = {
        let imageIO = (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap(UTType.init)
        return Set(imageIO + [.svg]).filter { $0.conforms(to: .image) && !$0.conforms(to: .pdf) }
    }()

    /// Any image type, including ones ImageIO can't decode — those still list, and render as
    /// "Can't open" in place rather than silently vanishing from the folder.
    public static func isViewable(_ type: UTType) -> Bool {
        type.conforms(to: .image) && !type.conforms(to: .pdf)
    }

    /// Uses the file's recorded content type when the file exists, else its extension.
    public static func isViewable(_ url: URL) -> Bool {
        let recorded = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        guard let type = recorded ?? UTType(filenameExtension: url.pathExtension) else { return false }
        return isViewable(type)
    }
}
