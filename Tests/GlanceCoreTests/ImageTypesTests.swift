import GlanceCore
import UniformTypeIdentifiers
import XCTest

final class ImageTypesTests: XCTestCase {
    func testEverydayRawAndVectorTypesAreViewable() {
        for ext in ["jpg", "JPG", "jpeg", "png", "heic", "HEIC", "gif", "webp", "tiff", "bmp", "svg", "cr3", "nef", "dng"] {
            XCTAssertTrue(ImageTypes.isViewable(URL(fileURLWithPath: "/nowhere/x.\(ext)")), ext)
        }
    }

    func testPDFAndNonImagesAreNotViewable() {
        for ext in ["pdf", "PDF", "txt", "mov", "zip", ""] {
            XCTAssertFalse(ImageTypes.isViewable(URL(fileURLWithPath: "/nowhere/x.\(ext)")), ext)
        }
    }

    func testSupportedExcludesPDFAndIncludesCoreFormats() {
        XCTAssertFalse(ImageTypes.supported.contains { $0.conforms(to: .pdf) })
        for type in [UTType.jpeg, .png, .heic, .gif, .webP, .tiff, .svg] {
            XCTAssertTrue(ImageTypes.supported.contains(type), type.identifier)
        }
        XCTAssertTrue(ImageTypes.supported.allSatisfy { $0.conforms(to: .image) })
    }

    func testClaimableTypesAreTheSupportedSetSorted() {
        XCTAssertEqual(Set(DefaultHandler.claimableTypes), ImageTypes.supported)
        XCTAssertEqual(DefaultHandler.claimableTypes.map(\.identifier), DefaultHandler.claimableTypes.map(\.identifier).sorted())
    }
}
