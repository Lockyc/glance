import XCTest
@testable import GlanceCore

final class LinkStoreTests: XCTestCase {
    private func f(_ p: String) -> URL { URL(fileURLWithPath: p).standardizedFileURL.absoluteURL }

    private var bigComparison: LaunchRequest {
        let dir = "/Users/someone/Developer/git.example.com/owner/project/.superpowers/icons/round-two"
        return .comparison((1...40).map { Variant(label: "v\($0)", files: [f("\(dir)/candidate-\($0)-full.png"),
                                                                             f("\(dir)/candidate-\($0)-dock.png")]) })
    }

    func testALinkStaysShortHoweverBigTheRequest() throws {
        let store = LinkStore(directory: Fixtures.tempDir())
        XCTAssertGreaterThan(bigComparison.url.absoluteString.count, 2048)
        let link = try store.link(for: bigComparison)
        XCTAssertLessThan(link.absoluteString.count, 64)
        XCTAssertEqual(store.request(for: link), bigComparison)
    }

    func testTheSameRequestGetsTheSameLink() throws {
        let store = LinkStore(directory: Fixtures.tempDir())
        let a = try store.link(for: .set([f("/tmp/a.png"), f("/tmp/b.png")]))
        let b = try store.link(for: .set([f("/tmp/a.png"), f("/tmp/b.png")]))
        let c = try store.link(for: .set([f("/tmp/b.png"), f("/tmp/a.png")]))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testALinkOpensFromAnotherStoreOnTheSameDirectory() throws {
        let dir = Fixtures.tempDir().appendingPathComponent("not/yet/made", isDirectory: true)
        let link = try LinkStore(directory: dir).link(for: .folder(f("/tmp/x")))
        XCTAssertEqual(LinkStore(directory: dir).request(for: link), .folder(f("/tmp/x")))
    }

    func testAnUnknownIdIsUnreadable() {
        let store = LinkStore(directory: Fixtures.tempDir())
        XCTAssertNil(store.request(for: URL(string: "glance://open?id=0123456789abcdef")!))
        XCTAssertNil(store.request(for: URL(string: "glance://open?id=../../etc/passwd")!))
    }

    func testAnInlineRequestStillOpens() {
        let store = LinkStore(directory: Fixtures.tempDir())
        let request = LaunchRequest.set([f("/tmp/a.png")])
        XCTAssertEqual(store.request(for: request.url), request)
        XCTAssertNil(store.request(for: URL(string: "glance://other")!))
    }
}
