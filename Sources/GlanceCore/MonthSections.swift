import Foundation

/// The grid's sections: one per calendar month of a tree's (sorted) dates, or one untitled
/// section when there are no dates. Maps between flat list positions and grid index paths.
public struct MonthSections: Equatable {
    public struct Section: Equatable {
        public let title: String?
        public let range: Range<Int>
        public init(title: String?, range: Range<Int>) {
            self.title = title
            self.range = range
        }
    }

    public let sections: [Section]

    public init(dates: [Date], count: Int, calendar: Calendar = .current) {
        guard !dates.isEmpty else {
            sections = [Section(title: nil, range: 0..<count)]
            return
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        var result: [Section] = []
        var start = 0
        for index in 1...dates.count where index == dates.count
            || !calendar.isDate(dates[index], equalTo: dates[start], toGranularity: .month) {
            result.append(Section(title: formatter.string(from: dates[start]), range: start..<index))
            start = index
        }
        sections = result
    }

    public func indexPath(for index: Int) -> IndexPath {
        var low = 0, high = sections.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if sections[mid].range.lowerBound <= index { low = mid } else { high = mid - 1 }
        }
        return IndexPath(item: index - sections[low].range.lowerBound, section: low)
    }

    public func index(for path: IndexPath) -> Int? {
        guard sections.indices.contains(path.section), path.item >= 0,
              path.item < sections[path.section].range.count else { return nil }
        return sections[path.section].range.lowerBound + path.item
    }
}
