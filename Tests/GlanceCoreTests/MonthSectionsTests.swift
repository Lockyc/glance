import GlanceCore
import XCTest

final class MonthSectionsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// 2025-03-10 is day 0; day 25 is 2025-04-04; day 300 is 2026-01-04.
    private func sections(_ days: [Int]) -> MonthSections {
        MonthSections(dates: days.map(Fixtures.day), count: days.count, calendar: utc)
    }

    func testGroupsConsecutiveDatesByMonth() {
        let s = sections([0, 1, 25, 300, 301])
        XCTAssertEqual(s.sections.map(\.title), ["March 2025", "April 2025", "January 2026"])
        XCTAssertEqual(s.sections.map(\.range), [0..<2, 2..<3, 3..<5])
    }

    func testSameMonthInDifferentYearsIsTwoSections() {
        XCTAssertEqual(sections([0, 365]).sections.map(\.title), ["March 2025", "March 2026"])
    }

    func testMapsBothWaysAcrossBoundaries() {
        let s = sections([0, 1, 25, 300, 301])
        for index in 0..<5 { XCTAssertEqual(s.index(for: s.indexPath(for: index)), index) }
        XCTAssertEqual(s.indexPath(for: 2), IndexPath(item: 0, section: 1))
        XCTAssertEqual(s.indexPath(for: 4), IndexPath(item: 1, section: 2))
    }

    func testOutOfRangePathIsNil() {
        let s = sections([0, 1])
        XCTAssertNil(s.index(for: IndexPath(item: 0, section: 3)))
        XCTAssertNil(s.index(for: IndexPath(item: 5, section: 0)))
    }

    func testNoDatesIsOneUntitledSection() {
        let s = MonthSections(dates: [], count: 3)
        XCTAssertEqual(s.sections, [MonthSections.Section(title: nil, range: 0..<3)])
        XCTAssertEqual(s.indexPath(for: 2), IndexPath(item: 2, section: 0))
    }

    func testEmptyIsOneEmptySection() {
        XCTAssertEqual(MonthSections(dates: [], count: 0).sections.map(\.range), [0..<0])
    }
}
