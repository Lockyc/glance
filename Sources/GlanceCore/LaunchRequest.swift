import Foundation

/// One labelled group of files in a comparison.
public struct Variant: Equatable, Codable {
    public let label: String
    public let files: [URL]

    public init(label: String, files: [URL]) {
        self.label = label
        self.files = files
    }
}

/// What a command-line launch asks the app to open. It travels from the CLI process to the
/// running app as a `glance://open?r=…` URL, so the two ends share one encoding.
public enum LaunchRequest: Equatable, Codable {
    case folder(URL)
    case set([URL])
    case comparison([Variant])

    public enum Parsed: Equatable {
        /// This process is the app: run it.
        case launchApp
        /// A bare `glance` in a terminal: open or activate the app, never become a second instance.
        case activateApp
        case help
        case open(LaunchRequest)
    }

    public struct ParseError: Error, Equatable {
        public let message: String
    }

    public static let usage = """
        usage: glance                                     open the app, or bring it forward
               glance -h | --help                         show this help
               glance <folder>                            open a folder
               glance <file>...                           open files as a set
               glance --variant <label> <file>... [--variant <label> <file>...]...
                                                          compare labelled variants side by side
        --variant starts a labelled group of files; two or more groups make a comparison.
        """

    /// Under Launch Services, no arguments or a leading Cocoa `-flag` means run the app. From a
    /// terminal the process must never become a second app instance, so a single-dash flag is
    /// only ever `-h` or an error.
    public static func parse(_ arguments: [String], workingDirectory: URL,
                             launchedByLaunchServices: Bool) throws -> Parsed {
        if launchedByLaunchServices {
            guard let first = arguments.first, !isSingleDash(first) else { return .launchApp }
        } else if arguments.isEmpty {
            return .activateApp
        }
        if arguments == ["--help"] || arguments == ["-h"] { return .help }

        func resolve(_ path: String) -> URL {
            URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL.absoluteURL
        }
        func isFolder(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        var variants: [Variant] = []
        var currentLabel: String?
        var currentFiles: [URL] = []
        var plain: [URL] = []

        func closeVariant() throws {
            guard let label = currentLabel else { return }
            guard !currentFiles.isEmpty else { throw ParseError(message: "--variant \(label) has no files") }
            variants.append(Variant(label: label, files: currentFiles))
            currentLabel = nil
            currentFiles = []
        }

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if argument == "--variant" {
                try closeVariant()
                guard index < arguments.count else { throw ParseError(message: "--variant needs a label") }
                currentLabel = arguments[index]
                index += 1
            } else if argument.hasPrefix("--") || isSingleDash(argument) {
                throw ParseError(message: "unknown option \(argument)")
            } else {
                let url = resolve(argument)
                if currentLabel != nil {
                    if isFolder(url) { throw ParseError(message: "a comparison takes files, not the folder \(argument)") }
                    currentFiles.append(url)
                } else if !variants.isEmpty {
                    throw ParseError(message: "\(argument) is outside any --variant")
                } else {
                    plain.append(url)
                }
            }
        }
        try closeVariant()

        if !variants.isEmpty {
            guard plain.isEmpty else { throw ParseError(message: "files before the first --variant") }
            return .open(.comparison(variants))
        }
        let folders = plain.filter(isFolder)
        if folders.isEmpty { return .open(.set(plain)) }
        guard plain.count == 1 else { throw ParseError(message: "a folder can't be combined with other paths") }
        return .open(.folder(plain[0]))
    }

    private static func isSingleDash(_ argument: String) -> Bool {
        argument.count > 1 && argument.hasPrefix("-") && !argument.hasPrefix("--")
    }

    /// `glance://open?r=<base64url JSON>`.
    public var url: URL {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "glance"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "r", value: encoded)]
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme == "glance", url.host == "open",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "r" })?.value else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let request = try? JSONDecoder().decode(LaunchRequest.self, from: data) else { return nil }
        self = request
    }

    /// The `.app` a bundled executable lives in, or nil for a bare binary.
    public static func appBundle(containing executable: URL) -> URL? {
        var url = executable.resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app" { return url }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
}
