import AppKit
import SwiftUI

// MARK: - TabBarView

/// The full polybar-style bar.
/// Left: numbered window tabs | Right: system info badges + clock.
struct TabBarView: View {
    let screen: NSScreen?

    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var overlayController: OverlayPanelController
    @ObservedObject private var settings = AppSettings.shared
    // Note: nowPlaying environment object still injected but now displayed only in Notch

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
        .background(BarTheme.surface.opacity(settings.barOpacity))
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
                availableWidth: max(proxy.size.width - rightPadding, 0)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.trailing, rightPadding)
        }
        .frame(height: TabBarConstants.barHeight)
    }

    private var unconstrainedRightRegion: some View {
        AdaptiveStatusRegion(
            availableWidth: .greatestFiniteMagnitude
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
    @State private var showOverflow = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var visibleCount: Int {
        WindowOverflowPolicy.visibleCount(total: windows.count,
            width: Double(max(0, availableWidth - leadingPadding - trailingPadding)))
    }

    private var results: [(offset: Int, element: WindowInfo)] {
        windows.enumerated().filter {
            WindowOverflowPolicy.matches(query: query, app: $0.element.appName, title: $0.element.title)
        }
    }

    var body: some View {
        HStack(spacing: WindowOverflowPolicy.spacing) {
            ForEach(Array(windows.prefix(visibleCount).enumerated()), id: \.element.id) { index, window in
                MiniTabView(window: window, index: index + 1,
                    isActive: window.id == activeWindowId, compactness: .regular,
                    onSelect: { onSelect(window) })
                    .frame(width: WindowOverflowPolicy.tabWidth)
            }
            if visibleCount < windows.count {
                Button { query = ""; showOverflow.toggle() } label: {
                    Text("+\(windows.count - visibleCount)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: WindowOverflowPolicy.overflowWidth, height: 24)
                        .background(BarTheme.tabBackground, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Search all windows")
                .accessibilityLabel("Search all windows, \(windows.count - visibleCount) more")
                .popover(isPresented: $showOverflow, arrowEdge: .bottom) { overflowContent }
            }
            if visibleCount == windows.count,
               availableWidth - leadingPadding - trailingPadding - CGFloat(windows.count) * (WindowOverflowPolicy.tabWidth + WindowOverflowPolicy.spacing) >= 150,
               let activeWindow = windows.first(where: { $0.id == activeWindowId }) {
                ActiveWindowTitleView(text: activeWindow.title.isEmpty ? activeWindow.appName : activeWindow.title, maxWidth: 180)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .clipped()
    }

    private var overflowContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Windows").font(.headline)
            TextField("Search apps and window titles", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { if let first = results.first { select(first.element) } }
            if results.isEmpty {
                Text("No matching windows").foregroundStyle(.secondary).padding(.vertical, 16)
            }
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(results, id: \.element.id) { index, window in
                        windowRow(window, index: index)
                    }
                }
            }
            .frame(height: min(320, CGFloat(max(1, results.count)) * 54))
            Text("Original tab numbers · ⌥1–9 shortcuts unchanged")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14).frame(width: 350)
        .onAppear { searchFocused = true }
    }

    private func windowRow(_ window: WindowInfo, index: Int) -> some View {
        Button { select(window) } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24).foregroundStyle(.secondary)
                if let icon = window.icon {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                } else {
                    Image(systemName: "macwindow").frame(width: 24, height: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.appName).font(.system(size: 12, weight: .semibold))
                    Text(window.title.isEmpty ? window.appName : window.title)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if window.id == activeWindowId { Image(systemName: "checkmark") }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ window: WindowInfo) {
        showOverflow = false
        onSelect(window)
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
    // Music info removed - now displayed in Notch
    
    var body: some View {
        SystemInfoView()
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}


