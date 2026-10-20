import XCTest
@testable import GlanceCore

final class LaunchRequestTests: XCTestCase {
    private func resolved(_ path: String, in dir: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL.absoluteURL
    }

    func testNoArgumentsOrCocoaArgumentsLaunchTheApp() throws {
        let dir = Fixtures.tempDir()
        XCTAssertEqual(try LaunchRequest.parse([], workingDirectory: dir), .launchApp)
        XCTAssertEqual(try LaunchRequest.parse(["-psn_0_123"], workingDirectory: dir), .launchApp)
        XCTAssertEqual(try LaunchRequest.parse(["-NSDocumentRevisionsDebugMode", "YES"], workingDirectory: dir), .launchApp)
    }

    func testHelp() throws {
        XCTAssertEqual(try LaunchRequest.parse(["--help"], workingDirectory: Fixtures.tempDir()), .help)
    }

    func testFilesMakeASetInOrderResolvedAgainstTheWorkingDirectory() throws {
        let dir = Fixtures.tempDir()
        Fixtures.touch(["b.png", "a b.png", "é.png"], in: dir)
        let parsed = try LaunchRequest.parse(["b.png", "./a b.png", "é.png", "b.png"], workingDirectory: dir)
        let expected = ["b.png", "a b.png", "é.png", "b.png"].map { resolved($0, in: dir) }
        XCTAssertEqual(parsed, .open(.set(expected)))
        XCTAssertEqual(try LaunchRequest.parse(["gone.png"], workingDirectory: dir),
                       .open(.set([resolved("gone.png", in: dir)])))
    }

    func testSingleFolderOpensTheFolder() throws {
        let dir = Fixtures.tempDir()
        XCTAssertEqual(try LaunchRequest.parse([dir.path], workingDirectory: dir),
                       .open(.folder(resolved(dir.path, in: dir))))
    }

    func testVariantsMakeAComparison() throws {
        let dir = Fixtures.tempDir()
        let parsed = try LaunchRequest.parse(
            ["--variant", "a", "a1.png", "a2.png", "--variant", "stacked", "s1.png"], workingDirectory: dir)
        let expected = LaunchRequest.comparison([
            Variant(label: "a", files: ["a1.png", "a2.png"].map { resolved($0, in: dir) }),
            Variant(label: "stacked", files: [resolved("s1.png", in: dir)]),
        ])
        XCTAssertEqual(parsed, .open(expected))
    }

    func testErrors() {
        let dir = Fixtures.tempDir()
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try! FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let other = dir.appendingPathComponent("other", isDirectory: true)
        try! FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let bad: [[String]] = [
            ["x.png", "--variant", "a", "y.png"],
            ["--variant"],
            ["--variant", "a", "--variant", "b", "x.png"],
            [sub.path, "x.png"],
            [sub.path, other.path],
            ["--variant", "a", sub.path],
            ["--bogus", "x.png"],
        ]
        for args in bad {
            XCTAssertThrowsError(try LaunchRequest.parse(args, workingDirectory: dir), "\(args)") {
                XCTAssertTrue($0 is LaunchRequest.ParseError)
            }
        }
    }

    func testURLRoundTrip() {
        let f = { (p: String) in URL(fileURLWithPath: p).standardizedFileURL.absoluteURL }
        let requests: [LaunchRequest] = [
            .folder(f("/tmp/a folder/é")),
            .set([f("/tmp/a b.png"), f("/tmp/é?&#.png"), f("/tmp/a b.png")]),
            .comparison([Variant(label: "a ?&#", files: [f("/tmp/x y.png")]),
                         Variant(label: "é", files: [f("/tmp/z.png"), f("/tmp/q#.png")])]),
        ]
        for r in requests {
            XCTAssertEqual(r.url.scheme, "glance")
            XCTAssertEqual(LaunchRequest(url: r.url), r)
        }
    }

    func testForeignURLIsRejected() {
        XCTAssertNil(LaunchRequest(url: URL(string: "glance://other")!))
        XCTAssertNil(LaunchRequest(url: URL(fileURLWithPath: "/tmp/a.png")))
    }

    func testAppBundle() {
        XCTAssertEqual(LaunchRequest.appBundle(containing: URL(fileURLWithPath: "/Applications/glance.app/Contents/MacOS/glance")),
                       URL(fileURLWithPath: "/Applications/glance.app"))
        XCTAssertNil(LaunchRequest.appBundle(containing: URL(fileURLWithPath: "/usr/local/bin/glance")))
    }
}
