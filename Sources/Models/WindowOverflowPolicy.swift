import Foundation

/// A fixed readable tab budget. Selection/search never reorder the source windows.
enum WindowOverflowPolicy {
    static let tabWidth: Double = 150
    static let spacing: Double = 3
    static let overflowWidth: Double = 54

    static func visibleCount(total: Int, width: Double) -> Int {
        guard total > 0, width.isFinite, width > 0 else { return 0 }
        let required = Double(total) * (tabWidth + spacing) - spacing
        if required <= width { return total }
        let capacity = max(0, floor((width - overflowWidth) / (tabWidth + spacing)))
        return Int(min(Double(total), capacity))
    }

    static func matches(query: String, app: String, title: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || app.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
