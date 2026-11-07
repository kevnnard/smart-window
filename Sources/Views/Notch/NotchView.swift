import SwiftUI

// MARK: - NotchLayout

/// Geometry of the notch badge for one screen.
struct NotchLayout: Equatable {
    /// Width of the physical notch (0 on screens without one).
    let notchWidth: CGFloat
    /// Height of the black bar on physical notched screen (safe area top inset).
    let physicalBarHeight: CGFloat
    /// Configured width (defaults to AppSettings.shared.notchCustomWidth if not provided).
    var customWidth: CGFloat = CGFloat(AppSettings.notchDefaultWidth)
    /// Configured height (defaults to AppSettings.shared.notchCustomHeight if not provided).
    var customHeight: CGFloat = CGFloat(AppSettings.notchDefaultHeight)

    static let bottomPadding: CGFloat = 6
    /// Height of the details that open below the compact row.
    static let expandedCardHeight: CGFloat = 180
    /// Narrowest drawer that still fits the artwork, controls and source badges.
    static let expandedMinWidth: CGFloat = 260
    /// How much wider than the compact notch the expanded card is (Notch tab, Expanded width).
    var expandedExtraWidth: CGFloat = 0

    var hasNotch: Bool { notchWidth > 0 }

    /// Height of the black bar (matches the menu bar on notched screens or user height if larger).
    var barHeight: CGFloat {
        hasNotch ? max(physicalBarHeight, customHeight) : customHeight
    }

    /// Smallest wing beside the camera notch: room for the artwork or the playback indicator.
    static let minWingWidth: CGFloat = 32
    /// Wing width from which the title and artist fit next to the artwork.
    static let wingTextWidth: CGFloat = 80
    /// Wing width from which the source name fits next to the playback indicator.
    static let wingLabelWidth: CGFloat = 90

    /// Content width on each side of the notch (notched screens). The configured width is the
    /// total width, notch included, so the wings take what is left on each side. Nothing can be
    /// drawn over the notch itself: the camera housing has no pixels.
    var wingWidth: CGFloat {
        guard hasNotch else { return 0 }
        return max(Self.minWingWidth, (customWidth - notchWidth) / 2)
    }

    /// Whether the left wing has room for the title (always true without a notch).
    var showsWingText: Bool { !hasNotch || wingWidth >= Self.wingTextWidth }
    /// Whether the right wing has room for the source name (always true without a notch).
    var showsSourceLabel: Bool { !hasNotch || wingWidth >= Self.wingLabelWidth }

    var contentWidth: CGFloat {
        hasNotch ? notchWidth + wingWidth * 2 : customWidth
    }

    var panelSize: CGSize {
        CGSize(width: contentWidth, height: barHeight + Self.bottomPadding)
    }

    /// Expanding opens a drawer: the compact row stays on top (around the camera on a notched
    /// screen) and the details open below it, so this is the height of that row.
    var expandedTopInset: CGFloat { barHeight }

    /// The drawer keeps the compact width (plus the configured extra) and grows down, widening
    /// only when the content would not fit.
    var expandedWidth: CGFloat { max(contentWidth + expandedExtraWidth, Self.expandedMinWidth) }

    /// The compact row as drawn on top of the open drawer: as wide as the drawer, with the
    /// camera gap still centered on a notched screen.
    var expandedRowLayout: NotchLayout {
        var row = self
        row.customWidth = expandedWidth
        return row
    }

    /// Window size for the compact pill or the expanded drawer. Shared by the view and the
    /// controller so the panel frame and the rendered content cannot diverge.
    func panelSize(expanded: Bool) -> CGSize {
        guard expanded else { return panelSize }
        return CGSize(width: expandedWidth,
                      height: expandedTopInset + Self.expandedCardHeight + Self.bottomPadding)
    }

    static func forScreen(_ screen: NSScreen, customWidth: CGFloat? = nil, customHeight: CGFloat? = nil) -> NotchLayout {
        // A display with a custom size (Notch tab, Per display) overrides the default size.
        let size = DisplayPreferences.shared.effectiveNotchSize(
            on: DisplayIdentity.key(for: screen),
            globalWidth: AppSettings.shared.notchCustomWidth,
            globalHeight: AppSettings.shared.notchCustomHeight)
        let width = customWidth ?? CGFloat(size.width)
        let height = customHeight ?? CGFloat(size.height)
        let extra = CGFloat(AppSettings.shared.notchExpandedExtraWidth)
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: width, customHeight: height,
                               expandedExtraWidth: extra)
        }
        let notch = screen.frame.width - left.width - right.width
        return NotchLayout(notchWidth: max(0, notch.rounded()), physicalBarHeight: inset, customWidth: width,
                           customHeight: height, expandedExtraWidth: extra)
    }
}

// MARK: - Primary display

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The menu bar display. `NSScreen.main` follows the key window, so it is not used here.
    static var primary: NSScreen? { screens.first }

    var isPrimary: Bool {
        guard let id = displayID else { return false }
        return id == NSScreen.primary?.displayID
    }
}

// MARK: - MarqueeText

/// Single-line, left-aligned text that slides back and forth only when it overflows.
/// The offset is a pure function of time, so transient layout sizes never leave a
/// stale animation running.
struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private let pointsPerSecond: Double = 20
    private let pauseSeconds: Double = 1.5

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: overflow <= 1)) { context in
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(GeometryReader { textGeo in
                        Color.clear
                            .onAppear { textWidth = textGeo.size.width }
                            .onChange(of: textGeo.size.width) { textWidth = $0 }
                    })
                    .offset(x: -offset(at: context.date))
            }
            .onAppear { containerWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { containerWidth = $0 }
        }
        .clipped()
    }

    /// Ping-pong between 0 and `overflow`, pausing at both ends.
    private func offset(at date: Date) -> CGFloat {
        guard overflow > 1 else { return 0 }
        let travel = Double(overflow) / pointsPerSecond
        let period = (travel + pauseSeconds) * 2
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        if t < pauseSeconds { return 0 }
        if t < pauseSeconds + travel { return CGFloat((t - pauseSeconds) * pointsPerSecond) }
        if t < pauseSeconds * 2 + travel { return overflow }
        return overflow - CGFloat((t - pauseSeconds * 2 - travel) * pointsPerSecond)
    }
}

// MARK: - BottomRoundedRectangle

struct BottomRoundedRectangle: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    radius: radius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                    radius: radius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(180),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - NotchView

/// Now-playing badge hugging the notch (or hanging from the top edge on external screens).
/// Supports compact notch pill state and expanded Dynamic Island card on hover/click.
struct NotchView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject private var settings = AppSettings.shared
    let layout: NotchLayout
    var screen: NSScreen? = nil
    var displayKey: String? = nil
    @ObservedObject var panelState: NotchPanelState
    @ObservedObject private var displayPreferences = DisplayPreferences.shared
    static let sourcePillWidth: CGFloat = 64
    static let sourcePillHeight: CGFloat = 20
    static let maxVisibleSources = 3

    private var isExpanded: Bool { panelState.isExpanded }

    /// First `max` sources, with the main source moved to the front when it would be hidden.
    nonisolated static func visibleSources(_ all: [AudioSourceInfo], max: Int) -> [AudioSourceInfo] {
        let limit = Swift.max(0, max)
        let head = Array(all.prefix(limit))
        guard limit > 0,
              let active = all.first(where: { $0.isActive }),
              !head.contains(where: { $0.id == active.id }) else { return head }
        return [active] + head.prefix(limit - 1)
    }

    /// "Artist — Album", either part alone, or nil when the source reports neither.
    nonisolated static func subtitle(artist: String, album: String) -> String? {
        let parts = [artist, album].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    /// Text under the transport buttons: the last command error, else why the source cannot be controlled.
    nonisolated static func controlStatus(error: String?, canControl: Bool,
                                          reason: String?) -> (text: String, isError: Bool)? {
        if let error { return (error, true) }
        if !canControl, let reason { return (reason, false) }
        return nil
    }

    /// Name of the main source, or nil when there is none (the service's default name is not a source).
    private var mainSourceName: String? {
        nowPlaying.hasPlayer ? nowPlaying.sourceDisplayName : nil
    }

    private var currentLayout: NotchLayout {
        if let screen = screen {
            return NotchLayout.forScreen(screen)
        }
        return NotchLayout(
            notchWidth: layout.notchWidth,
            physicalBarHeight: layout.physicalBarHeight,
            customWidth: CGFloat(settings.notchCustomWidth),
            customHeight: CGFloat(settings.notchCustomHeight)
        )
    }

    private var isVisible: Bool {
        let isMainOnly = !settings.notchShowOnAllDisplays
        if isMainOnly, let screen = screen, !screen.isPrimary {
            return false
        }
        let displayAllowed = displayPreferences.nowPlayingVisible(on: displayKey)
        if settings.notchAlwaysVisible {
            return displayAllowed
        } else {
            return nowPlaying.hasPlayer && displayAllowed
        }
    }

    var sourceAccentColor: Color {
        switch nowPlaying.sourceCategory {
        case "spotify":
            return Color(red: 29/255, green: 185/255, blue: 84/255)
        case "youtube":
            return Color(red: 255/255, green: 0/255, blue: 51/255)
        case "ghostty":
            return Color(red: 56/255, green: 189/255, blue: 248/255)
        case "music":
            return Color(red: 250/255, green: 36/255, blue: 60/255)
        default:
            return Color(red: 168/255, green: 85/255, blue: 247/255)
        }
    }

    var sourceIconText: String {
        switch nowPlaying.sourceCategory {
        case "spotify": return "♫"
        case "youtube": return "▶"
        case "ghostty": return "❯"
        case "music": return "♪"
        default: return "♬"
        }
    }

    var body: some View {
        let activeLayout = currentLayout
        let cardWidth = activeLayout.panelSize(expanded: true).width
        let activeSize = activeLayout.panelSize(expanded: isExpanded)

        ZStack(alignment: .top) {
            if isVisible {
                if isExpanded {
                    let row = activeLayout.expandedRowLayout
                    let drawer = BottomRoundedRectangle(radius: 22)
                    VStack(spacing: 0) {
                        // The compact row stays where it was; the details open below it.
                        compactContent(for: row)
                            .frame(width: cardWidth, height: row.barHeight)
                        expandedIslandCard(width: cardWidth)
                    }
                    .background(notchBackground)
                    .clipShape(drawer)
                    .overlay(drawer.stroke(Color.white.opacity(settings.notchBadgeMatchesBar ? 0.14 : 0), lineWidth: 1))
                    // The open drawer floats over windows, so it keeps a shadow in both styles.
                    .shadow(color: .black.opacity(0.8), radius: 24, y: 10)
                    .transition(.opacity)
                } else {
                    compactContent(for: activeLayout)
                        .frame(width: activeLayout.contentWidth, height: activeLayout.barHeight)
                        .background(notchBackground)
                        .clipShape(BottomRoundedRectangle(radius: activeLayout.hasNotch ? 12 : 14))
                        // Black matches the physical notch: no outline or shadow, so it blends with
                        // the camera housing. The bar color needs both to stand off the wallpaper.
                        .overlay(
                            BottomRoundedRectangle(radius: activeLayout.hasNotch ? 12 : 14)
                                .stroke(Color.white.opacity(settings.notchBadgeMatchesBar ? 0.12 : 0), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(settings.notchBadgeMatchesBar ? 0.35 : 0), radius: 4, y: 2)
                        .contentShape(Rectangle())
                        // Hover is tracked by the panel's hosting view (NotchController); a click also expands.
                        .onTapGesture { panelState.expand() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(width: activeSize.width, height: activeSize.height, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: nowPlaying.isPlaying)
        .onChange(of: isVisible) { visible in
            if !visible { panelState.collapse() }
        }
    }

    // MARK: - Compact Content

    @ViewBuilder
    private func compactContent(for activeLayout: NotchLayout) -> some View {
        if activeLayout.hasNotch {
            if nowPlaying.hasPlayer {
                HStack(spacing: 0) {
                    compactLeftInfo(showsText: activeLayout.showsWingText)
                        .frame(width: activeLayout.wingWidth)
                    Color.clear
                        .frame(width: activeLayout.notchWidth)
                    compactRightInfo(showsLabel: activeLayout.showsSourceLabel)
                        .frame(width: activeLayout.wingWidth)
                }
            } else {
                HStack(spacing: 0) {
                    Color.clear.frame(width: activeLayout.wingWidth)
                    Color.clear.frame(width: activeLayout.notchWidth)
                    Color.clear.frame(width: activeLayout.wingWidth)
                }
            }
        } else {
            if nowPlaying.hasPlayer {
                HStack(spacing: 10) {
                    compactLeftInfo(showsText: true)
                    Spacer(minLength: 0)
                    compactRightInfo(showsLabel: true)
                }
                .padding(.horizontal, 10)
            } else {
                idleNotchContent
            }
        }
    }

    /// Artwork, plus title and artist when the wing is wide enough.
    private func compactLeftInfo(showsText: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(sourceAccentColor)
                if let image = nowPlaying.artwork ?? nowPlaying.playerIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Text(sourceIconText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .frame(width: 17, height: 17)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            if showsText {
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(
                    text: nowPlaying.trackTitle.isEmpty ? nowPlaying.sourceDisplayName : nowPlaying.trackTitle,
                    font: .system(size: 11, weight: .semibold, design: .rounded)
                )
                .foregroundColor(.white)
                .frame(height: 13)

                if !nowPlaying.artistName.isEmpty {
                    MarqueeText(
                        text: nowPlaying.artistName,
                        font: .system(size: 9, weight: .medium, design: .rounded)
                    )
                    .foregroundColor(.white.opacity(0.6))
                    .frame(height: 11)
                }
            }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: showsText ? .leading : .center)
    }

    /// Playback indicator, plus the source name when the wing is wide enough.
    private func compactRightInfo(showsLabel: Bool) -> some View {
        HStack(spacing: 6) {
            if showsLabel {
                Text(nowPlaying.sourceDisplayName.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            if nowPlaying.isPlaying {
                WaveformBars(color: sourceAccentColor)
                    .frame(width: 15, height: 12)
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.trailing, showsLabel ? 10 : 0)
        .frame(maxWidth: .infinity, alignment: showsLabel ? .trailing : .center)
    }

    private var idleNotchContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            Text("SmartWindow")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    // MARK: - Expanded Dynamic Island Card

    /// Details that open below the compact row: app badges, artwork, track, controls and progress.
    /// The compact row above already names the source, so the header only holds the badges.
    private func expandedIslandCard(width: CGFloat) -> some View {
        VStack(spacing: 10) {
            // Header: app selector badges + collapse
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                // Multi-app selector pills
                HStack(spacing: 5) {
                    ForEach(Self.visibleSources(nowPlaying.detectedSources, max: Self.maxVisibleSources)) { source in
                        Button {
                            nowPlaying.selectSource(source.id)
                        } label: {
                            HStack(spacing: 3) {
                                if let icon = source.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 10, height: 10)
                                }
                                Text(source.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(.horizontal, 6)
                            // Every pill keeps the same box so a long app name never resizes its neighbours.
                            .frame(width: Self.sourcePillWidth, height: Self.sourcePillHeight)
                            .background(source.isActive ? Color.white.opacity(0.2) : Color.white.opacity(0.06), in: Capsule())
                            .foregroundColor(source.isActive ? .white : .white.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .help(source.name)
                    }

                    Button {
                        panelState.collapse()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse to notch")
                }
            }

            // Middle: Artwork + Track details
            HStack(spacing: 14) {
                ZStack {
                    LinearGradient(
                        colors: [sourceAccentColor.opacity(0.85), Color.black.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if let image = nowPlaying.artwork ?? nowPlaying.playerIcon {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                .contentShape(Rectangle())
                .onTapGesture { nowPlaying.openPlayer() }

                // The header already names the app, so no separate app line is shown here.
                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.trackTitle.isEmpty ? (mainSourceName ?? "Nothing playing") : nowPlaying.trackTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let subtitle = Self.subtitle(artist: nowPlaying.artistName, album: nowPlaying.albumName) {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    progressSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Bottom: Controls + state, with the control status under the buttons
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 14) {
                    // Transport buttons
                    HStack(spacing: 10) {
                        Button { nowPlaying.perform(.previous) } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button { nowPlaying.perform(.playPause) } label: {
                            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 32, height: 32)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button { nowPlaying.perform(.next) } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(!nowPlaying.canControl)
                    .opacity(nowPlaying.canControl ? 1 : 0.4)

                    // Playback state, also shown when the source reports no position.
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if nowPlaying.isPlaying {
                            WaveformBars(color: sourceAccentColor)
                                .frame(width: 18, height: 14)
                        }
                        Text(nowPlaying.isPlaying ? "Playing" : "Paused")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                if let status = Self.controlStatus(error: nowPlaying.lastCommandError,
                                                   canControl: nowPlaying.canControl,
                                                   reason: nowPlaying.controlUnavailableReason) {
                    Text(status.text)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(status.isError ? .red.opacity(0.85) : .white.opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(status.text)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        // Top-aligned so a status line appearing under the controls never shifts the rows above.
        .frame(width: width, height: NotchLayout.expandedCardHeight, alignment: .top)
    }

    /// Opaque black like the physical notch (the default), or the bar color when chosen in Settings.
    private var notchBackground: Color {
        settings.notchBadgeMatchesBar ? BarTheme.surface : Color.black
    }

    // MARK: - Progress

    /// Ticks once a second only while playing; paused or unknown positions need no timer.
    @ViewBuilder
    private var progressSection: some View {
        if nowPlaying.playbackRate > 0 {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                progressRow(at: context.date)
            }
        } else {
            progressRow(at: Date())
        }
    }

    /// Bar with elapsed and total time, or nothing when the source reports no duration or elapsed time.
    @ViewBuilder
    private func progressRow(at date: Date) -> some View {
        if let duration = nowPlaying.duration,
           let position = NotchProgress.position(elapsed: nowPlaying.elapsedTime,
                                                 timestamp: nowPlaying.elapsedTimestamp,
                                                 rate: nowPlaying.playbackRate,
                                                 duration: duration, now: date) {
            VStack(spacing: 3) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(sourceAccentColor)
                            .frame(width: geometry.size.width * CGFloat(position / duration))
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(NotchProgress.format(position))
                    Spacer(minLength: 0)
                    Text(NotchProgress.format(duration))
                }
                .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - WaveformBars

/// Four bouncing bars, animated only while shown.
struct WaveformBars: View {
    var color: Color = Color(red: 0.11, green: 0.84, blue: 0.38)
    @State private var animate = false
    private let heights: [CGFloat] = [0.45, 1.0, 0.65, 0.85]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3)
                    .scaleEffect(y: animate ? heights[i] : 0.25, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.4 + Double(i) * 0.12).repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
