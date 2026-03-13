import AppKit
import Foundation

// MARK: - WindowInfo

/// Represents a macOS window captured via the Accessibility API.
struct WindowInfo: Identifiable, Hashable {
    let id: UUID
    let pid: pid_t
    let windowNumber: Int
    let appName: String
    let appBundleIdentifier: String?
    let title: String
    let icon: NSImage?
    let isMinimized: Bool
    let isOnScreen: Bool
    let frame: CGRect

    // Accessibility element reference (not Hashable, excluded from conformance)
    let axElement: AXUIElement?

    init(
        pid: pid_t,
        windowNumber: Int = 0,
        appName: String,
        appBundleIdentifier: String? = nil,
        title: String,
        icon: NSImage? = nil,
        isMinimized: Bool = false,
        isOnScreen: Bool = true,
        frame: CGRect = .zero,
        axElement: AXUIElement? = nil
    ) {
        self.id = UUID()
        self.pid = pid
        self.windowNumber = windowNumber
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.title = title
        self.icon = icon
        self.isMinimized = isMinimized
        self.isOnScreen = isOnScreen
        self.frame = frame
        self.axElement = axElement
    }

    // MARK: - Display Helpers

    /// Returns a short display title (truncated if needed)
    var displayTitle: String {
        let maxLength = 30
        if title.count > maxLength {
            return String(title.prefix(maxLength)) + "…"
        }
        return title.isEmpty ? appName : title
    }

    func shortAppName(maxLength: Int) -> String {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }

        let words = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if let firstWord = words.first, firstWord.count <= maxLength {
            return firstWord
        }

        let shortened = String(trimmed.prefix(max(1, maxLength - 1)))
        return shortened + "…"
    }

    // MARK: - Hashable

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - WindowGroup

/// Groups windows by application.
struct WindowGroup: Identifiable {
    let id: String // bundleIdentifier or appName
    let appName: String
    let icon: NSImage?
    let windows: [WindowInfo]

    var windowCount: Int { windows.count }
}
