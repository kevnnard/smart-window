import AppKit
import SwiftUI

// MARK: - TabBarView

/// The full polybar-style bar.
/// Left: numbered window tabs | Right: system info badges + clock.
struct TabBarView: View {
    let screen: NSScreen?

    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var overlayController: OverlayPanelController
    @EnvironmentObject var nowPlaying: NowPlayingService

    private let leftPadding: CGFloat = 8
    private let rightPadding: CGFloat = 10
    private let regionSpacing: CGFloat = 12

    private var layout: TopBarScreenLayout {
        TopBarScreenLayout(screen: screen)
    }

    var body: some View {
        Group {
            if layout.hasNotch {
                notchedBar
            } else {
                standardBar
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: TabBarConstants.barHeight)
        .background(BarTheme.background)
    }

    private var notchedBar: some View {
        ZStack {
            tabRegion
                .frame(width: layout.leftRegionWidth, alignment: .leading)
                .padding(.leading, layout.leftRegionInset)
                .frame(maxWidth: .infinity, alignment: .leading)

            constrainedRightRegion
                .frame(width: layout.rightRegionWidth, alignment: .trailing)
                .padding(.trailing, layout.rightRegionInset)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var standardBar: some View {
        HStack(spacing: 0) {
            tabRegion
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: regionSpacing)

            unconstrainedRightRegion
        }
    }

    private var tabRegion: some View {
        GeometryReader { proxy in
            AdaptiveTabStrip(
                windows: windowManager.windows,
                activeWindowId: windowManager.activeWindowId,
                availableWidth: max(proxy.size.width, 0),
                leadingPadding: leftPadding,
                trailingPadding: 6,
                onSelect: windowManager.focus
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: TabBarConstants.barHeight)
    }

    private var constrainedRightRegion: some View {
        GeometryReader { proxy in
            AdaptiveStatusRegion(
                availableWidth: max(proxy.size.width - rightPadding, 0),
                hasTrack: nowPlaying.hasTrack,
                displayText: nowPlaying.displayText
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.trailing, rightPadding)
        }
        .frame(height: TabBarConstants.barHeight)
    }

    private var unconstrainedRightRegion: some View {
        AdaptiveStatusRegion(
            availableWidth: .greatestFiniteMagnitude,
            hasTrack: nowPlaying.hasTrack,
            displayText: nowPlaying.displayText
        )
        .padding(.trailing, rightPadding)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - AdaptiveTabStrip

private struct AdaptiveTabStrip: View {
    let windows: [WindowInfo]
    let activeWindowId: UUID?
    let availableWidth: CGFloat
    let leadingPadding: CGFloat
    let trailingPadding: CGFloat
    let onSelect: (WindowInfo) -> Void

    private var compactness: MiniTabCompactness {
        let windowCount = max(windows.count, 1)
        let usableWidth = max(availableWidth - leadingPadding - trailingPadding, 0)
        let widthPerTab = usableWidth / CGFloat(windowCount)

        if widthPerTab >= 96 {
            return .regular
        }

        if widthPerTab >= 68 {
            return .compact
        }

        return .minimal
    }

    private var activeWindow: WindowInfo? {
        guard let activeWindowId else { return nil }
        return windows.first(where: { $0.id == activeWindowId })
    }

    private var showsActiveWindowTitle: Bool {
        guard activeWindow != nil, compactness != .minimal, !windows.isEmpty else {
            return false
        }

        let requiredTabWidth = CGFloat(windows.count) * compactness.estimatedWidth
        let spareWidth = availableWidth - requiredTabWidth - leadingPadding - trailingPadding

        switch compactness {
        case .regular:
            return spareWidth >= 150
        case .compact:
            return spareWidth >= 110
        case .minimal:
            return false
        }
    }

    private var activeWindowTitleWidth: CGFloat {
        switch compactness {
        case .regular:
            return 180
        case .compact:
            return 120
        case .minimal:
            return 0
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    MiniTabView(
                        window: window,
                        index: index + 1,
                        isActive: window.id == activeWindowId,
                        compactness: compactness,
                        onSelect: {
                            onSelect(window)
                        }
                    )
                }

                if showsActiveWindowTitle,
                   let activeWindow {
                    ActiveWindowTitleView(
                        text: activeWindow.title.isEmpty ? activeWindow.appName : activeWindow.title,
                        maxWidth: activeWindowTitleWidth
                    )
                }
            }
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
        }
        .clipped()
    }
}

private struct ActiveWindowTitleView: View {
    let text: String
    let maxWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(">")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(BarTheme.dimText)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(BarTheme.inactiveText)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - AdaptiveStatusRegion

private struct AdaptiveStatusRegion: View {
    let availableWidth: CGFloat
    let hasTrack: Bool
    let displayText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if hasTrack, availableWidth >= 560 {
                statusRow(nowPlayingWidth: 220)
            }

            if hasTrack, availableWidth >= 470 {
                statusRow(nowPlayingWidth: 120)
            }

            statusRow(nowPlayingWidth: nil)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func statusRow(nowPlayingWidth: CGFloat?) -> some View {
        HStack(spacing: 8) {
            if let nowPlayingWidth {
                NowPlayingBadge(displayText: displayText, maxWidth: nowPlayingWidth)
            }

            SystemInfoView()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - NowPlayingBadge

/// Spotify/Music now playing: ♫ Artist — Track
struct NowPlayingBadge: View {
    let displayText: String
    var maxWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "music.note")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(BarTheme.badgeMusic)

            Text(displayText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(BarTheme.inactiveText)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(BarTheme.badgeMusic.opacity(0.12))
        )
    }
}
