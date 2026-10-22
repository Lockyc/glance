import Foundation
import UniformTypeIdentifiers

/// Handing images to Excerpt to mark up: several at once open there as one series.
public enum ExternalEditor {
    public static let excerptBundleIdentifier = "com.lockyc.excerpt"

    /// Why `urls` can't go to Excerpt, in the words the disabled command shows; nil when they can.
    public static func refusal(for urls: [URL], installed: Bool) -> String? {
        if urls.isEmpty { return "No image selected" }
        if !installed { return "Excerpt isn't installed" }
        let allPNG = urls.allSatisfy { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .png) == true }
        return allPNG ? nil : "Excerpt edits PNG images only"
    }
}
