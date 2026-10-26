import AppKit

/// Content-sized readable tabs with an explicit overflow-button budget. Selection/search never reorder the source windows.
enum WindowOverflowPolicy {
    static let tabWidth: Double = 150
    static let spacing: Double = 3
    static let overflowWidth: Double = 54

    static func visibleCount(widths: [Double], width: Double) -> Int {
        guard !widths.isEmpty, width.isFinite, width > 0 else { return 0 }
        let required = widths.reduce(0, +) + Double(widths.count - 1) * spacing
        if required <= width { return widths.count }
        var occupied = overflowWidth
        var count = 0
        for tab in widths {
            guard occupied + spacing + tab <= width else { break }
            occupied += spacing + tab
            count += 1
        }
        return count
    }

    static func measuredTabWidth(appName: String, index: Int) -> Double {
        // Budget the heavier selected font too, so selecting a tab never shifts its neighbors.
        let label = (appName as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
        let number = (String(index) as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)]).width
        let dot = ("·" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .bold)]).width
        return min(tabWidth, max(88, ceil(Double(label + number + dot) + 30)))
    }

    static func matches(query: String, app: String, title: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || app.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
