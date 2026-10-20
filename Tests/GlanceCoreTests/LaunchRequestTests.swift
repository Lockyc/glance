import XCTest
@testable import GlanceCore

final class LaunchRequestTests: XCTestCase {
    private func resolved(_ path: String, in dir: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL.absoluteURL
    }

    private func parse(_ arguments: [String], in dir: URL = Fixtures.tempDir(),
                       launchServices: Bool = false) throws -> LaunchRequest.Parsed {
        try LaunchRequest.parse(arguments, workingDirectory: dir, launchedByLaunchServices: launchServices)
    }

    func testUnderLaunchServicesNoArgumentsOrCocoaArgumentsLaunchTheApp() throws {
        XCTAssertEqual(try parse([], launchServices: true), .launchApp)
        XCTAssertEqual(try parse(["-psn_0_1"], launchServices: true), .launchApp)
        XCTAssertEqual(try parse(["-NSDocumentRevisionsDebugMode", "YES"], launchServices: true), .launchApp)
        XCTAssertEqual(try parse(["-h"], launchServices: true), .launchApp)
        XCTAssertEqual(try parse(["-x"], launchServices: true), .launchApp)
    }

    func testFromATerminalNothingStartsASecondInstance() throws {
        XCTAssertEqual(try parse([]), .activateApp)
        XCTAssertEqual(try parse(["-h"]), .help)
        for args in [["-psn_0_1"], ["-NSDocumentRevisionsDebugMode", "YES"], ["-x"], ["a.png", "-x"]] {
            XCTAssertThrowsError(try parse(args), "\(args)") {
                XCTAssertEqual(($0 as? LaunchRequest.ParseError)?.message, "unknown option \(args.first { $0.hasPrefix("-") }!)")
            }
        }
    }

    func testHelp() throws {
        XCTAssertEqual(try parse(["--help"]), .help)
        XCTAssertEqual(try parse(["--help"], launchServices: true), .help)
    }

    func testFilesMakeASetInOrderResolvedAgainstTheWorkingDirectory() throws {
        let dir = Fixtures.tempDir()
        Fixtures.touch(["b.png", "a b.png", "é.png"], in: dir)
        let parsed = try parse(["b.png", "./a b.png", "é.png", "b.png"], in: dir)
        let expected = ["b.png", "a b.png", "é.png", "b.png"].map { resolved($0, in: dir) }
        XCTAssertEqual(parsed, .open(.set(expected)))
        XCTAssertEqual(try parse(["gone.png"], in: dir), .open(.set([resolved("gone.png", in: dir)])))
    }

    func testSingleFolderOpensTheFolder() throws {
        let dir = Fixtures.tempDir()
        XCTAssertEqual(try parse([dir.path], in: dir), .open(.folder(resolved(dir.path, in: dir))))
    }

    func testVariantsMakeAComparison() throws {
        let dir = Fixtures.tempDir()
        let parsed = try parse(["--variant", "a", "a1.png", "a2.png", "--variant", "stacked", "s1.png"], in: dir)
        let expected = LaunchRequest.comparison([
            Variant(label: "a", files: ["a1.png", "a2.png"].map { resolved($0, in: dir) }),
            Variant(label: "stacked", files: [resolved("s1.png", in: dir)]),
        ])
        XCTAssertEqual(parsed, .open(expected))
    }

    func testASingleVariantIsAComparison() throws {
        let dir = Fixtures.tempDir()
        XCTAssertEqual(try parse(["--variant", "only", "x.png"], in: dir),
                       .open(.comparison([Variant(label: "only", files: [resolved("x.png", in: dir)])])))
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
            XCTAssertThrowsError(try parse(args, in: dir), "\(args)") {
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
