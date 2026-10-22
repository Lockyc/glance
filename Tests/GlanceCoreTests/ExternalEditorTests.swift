import Foundation
@testable import GlanceCore
import XCTest

final class ExternalEditorTests: XCTestCase {
    let png = URL(fileURLWithPath: "/l/a.png")
    let jpeg = URL(fileURLWithPath: "/l/b.jpg")

    func testPNGsGoToExcerpt() {
        XCTAssertNil(ExternalEditor.refusal(for: [png, URL(fileURLWithPath: "/l/c.PNG")], installed: true))
    }

    func testEachRefusalSaysWhy() {
        XCTAssertEqual(ExternalEditor.refusal(for: [], installed: true), "No image selected")
        XCTAssertEqual(ExternalEditor.refusal(for: [png], installed: false), "Excerpt isn't installed")
        XCTAssertEqual(ExternalEditor.refusal(for: [png, jpeg], installed: true), "Excerpt edits PNG images only")
    }
}
