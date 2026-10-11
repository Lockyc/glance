import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Fixtures {
    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glance-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func touch(_ names: [String], in dir: URL) {
        for name in names {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
    }
}
