import AppKit
import UniformTypeIdentifiers

/// What Copy and a drag out of the viewer hand other apps: each file, as Finder's Copy does, and
/// for a lone image in a common format its bytes too, so it pastes as a picture where files don't.
enum ImagePasteboard {
    private static let dataTypes: [UTType] = [.png, .jpeg, .tiff, .gif, .heic]

    static func item(for url: URL, withData: Bool) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if withData, let type = UTType(filenameExtension: url.pathExtension), dataTypes.contains(where: type.conforms(to:)),
           let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        return item
    }

    static func write(_ urls: [URL], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { item(for: $0, withData: urls.count == 1) })
    }
}
