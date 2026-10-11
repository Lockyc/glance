import AppKit
import UniformTypeIdentifiers

/// Makes glance the default app for every type in `ImageTypes.supported`.
public enum DefaultHandler {
    public static var claimableTypes: [UTType] {
        ImageTypes.supported.sorted { $0.identifier < $1.identifier }
    }

    /// Calls `completion` on the main queue with the number of types claimed and those that failed.
    public static func claimAll(appURL: URL, completion: @escaping (_ claimed: Int, _ failed: [UTType]) -> Void) {
        let types = claimableTypes
        let group = DispatchGroup()
        let lock = NSLock()
        var failed: [UTType] = []
        for type in types {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
                if error != nil { lock.withLock { failed.append(type) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(types.count - failed.count, failed) }
    }
}
