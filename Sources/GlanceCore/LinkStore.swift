import CryptoKit
import Foundation

/// Keeps what a `glance --link` link opens, so the link is a short `glance://open?id=<id>` however
/// many files it names. A terminal drops a hyperlink whose target outgrows its escape-sequence
/// buffer (Ghostty's is 2 KB), and an inline `?r=` request for a few dozen paths passes that. The id
/// is the request's hash, so the same view always gets the same link, and an entry is never
/// removed: a link pasted into a note keeps working. A link opens only on the Mac that made it,
/// which its local file paths already require.
public struct LinkStore {
    public static let standard = LinkStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("glance/links", isDirectory: true))

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Stores `request` and returns its short link.
    public func link(for request: LaunchRequest) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        let id = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(id), options: .atomic)
        var components = URLComponents()
        components.scheme = "glance"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }

    /// The request a `glance://` URL opens: a stored `?id=` link or an inline `?r=` request.
    public func request(for url: URL) -> LaunchRequest? {
        guard url.scheme == "glance", url.host == "open" else { return nil }
        guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value else { return LaunchRequest(url: url) }
        guard id.allSatisfy(\.isHexDigit), let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(LaunchRequest.self, from: data)
    }

    private func file(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }
}
