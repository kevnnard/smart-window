import SwiftUI

// MARK: - Theme Colors

enum BarTheme {
    static let background    = Color(red: 0.10, green: 0.10, blue: 0.12, opacity: 0.58)  // dark glass overlay
    static let tabBackground = Color(red: 0.16, green: 0.16, blue: 0.19)  // #292930
    static let activeTab     = Color(red: 0.30, green: 0.70, blue: 0.45)  // #4db373 (subtle green)
    static let activeText    = Color(red: 0.10, green: 0.10, blue: 0.12)  // dark text on green
    static let inactiveText  = Color(red: 0.70, green: 0.70, blue: 0.72)  // #b3b3b8
    static let dimText       = Color(red: 0.45, green: 0.45, blue: 0.48)  // #737378
    static let separator     = Color(red: 0.25, green: 0.25, blue: 0.28)  // #404048

    // System info badge colors
    static let badgeRam      = Color(red: 0.95, green: 0.35, blue: 0.35)  // red
    static let badgeCpu      = Color(red: 0.30, green: 0.75, blue: 0.95)  // cyan
    static let badgeGpu      = Color(red: 0.85, green: 0.55, blue: 0.95)  // magenta/violet
    static let badgeBattery  = Color(red: 0.40, green: 0.85, blue: 0.40)  // green
    static let badgeVolume   = Color(red: 0.60, green: 0.45, blue: 0.90)  // purple
    static let badgeMic      = Color(red: 0.95, green: 0.60, blue: 0.20)  // orange
    static let badgeDate     = Color(red: 0.55, green: 0.75, blue: 0.95)  // light blue
    static let badgeMusic    = Color(red: 0.30, green: 0.85, blue: 0.55)  // spotify green
}

// MARK: - MiniTabView

enum MiniTabCompactness {
    case regular
    case compact
    case minimal

    var estimatedWidth: CGFloat {
        switch self {
        case .regular:
            return 92
        case .compact:
            return 70
        case .minimal:
            return 50
        }
    }
}

/// Polybar-style tab: `[index · AppName]`
/// Active tab = subtle green background with dark text. No close button, no hover effect.
struct MiniTabView: View {
    let window: WindowInfo
    let index: Int
    let isActive: Bool
    let compactness: MiniTabCompactness
    let onSelect: () -> Void

    private var labelText: String {
        switch compactness {
        case .regular:
            return window.appName
        case .compact:
            return isActive ? window.appName : window.shortAppName(maxLength: 10)
        case .minimal:
            return isActive ? window.shortAppName(maxLength: 12) : window.shortAppName(maxLength: 4)
        }
    }

    private var labelWidth: CGFloat? {
        switch compactness {
        case .regular:
            return isActive ? 120 : 88
        case .compact:
            return isActive ? 96 : 58
        case .minimal:
            return isActive ? 72 : 28
        }
    }

    private var horizontalPadding: CGFloat {
        switch compactness {
        case .regular:
            return 10
        case .compact:
            return 8
        case .minimal:
            return 6
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            // Index number
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isActive ? BarTheme.activeText : BarTheme.dimText)

            // Separator dot
            Text("·")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isActive ? BarTheme.activeText.opacity(0.6) : BarTheme.dimText)

            // App name
            Text(labelText)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? BarTheme.activeText : BarTheme.inactiveText)
                .frame(maxWidth: labelWidth, alignment: .leading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? BarTheme.activeTab : BarTheme.tabBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isActive ? BarTheme.activeTab.opacity(0.6) : BarTheme.separator.opacity(0.4),
                    lineWidth: isActive ? 1 : 0.5
                )
        )
        .onTapGesture(perform: onSelect)
    }
}
