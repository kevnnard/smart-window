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

    var hasNotch: Bool { notchWidth > 0 }

    /// Height of the black bar (matches the menu bar on notched screens or user height if larger).
    var barHeight: CGFloat {
        hasNotch ? max(physicalBarHeight, customHeight) : customHeight
    }

    /// Content width on each side of the notch (notched screens).
    /// Scales proportionally with customWidth: 150pt wing at default 280pt customWidth.
    var wingWidth: CGFloat {
        guard hasNotch else { return 0 }
        return max(50, (customWidth / CGFloat(AppSettings.notchDefaultWidth)) * 150.0)
    }

    var contentWidth: CGFloat {
        hasNotch ? notchWidth + wingWidth * 2 : customWidth
    }

    var panelSize: CGSize {
        CGSize(width: contentWidth, height: barHeight + Self.bottomPadding)
    }

    static func forScreen(_ screen: NSScreen, customWidth: CGFloat? = nil, customHeight: CGFloat? = nil) -> NotchLayout {
        let width = customWidth ?? CGFloat(AppSettings.shared.notchCustomWidth)
        let height = customHeight ?? CGFloat(AppSettings.shared.notchCustomHeight)
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: width, customHeight: height)
        }
        let notch = screen.frame.width - left.width - right.width
        return NotchLayout(notchWidth: max(0, notch.rounded()), physicalBarHeight: inset, customWidth: width, customHeight: height)
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
    var onExpandChange: ((Bool) -> Void)? = nil
    @ObservedObject private var displayPreferences = DisplayPreferences.shared
    static let sourcePillWidth: CGFloat = 64
    static let sourcePillHeight: CGFloat = 20
    static let sourceBadgeMaxWidth: CGFloat = 160
    @State private var isExpanded = false
    @State private var isHovering = false

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
        if isMainOnly, let screen = screen, let main = NSScreen.main {
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let mainID = main.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if screenID != mainID {
                return false
            }
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
        let cardWidth = max(activeLayout.contentWidth, 440)
        let activeWidth = isExpanded ? cardWidth : activeLayout.contentWidth
        let activeHeight = isExpanded ? 180 : activeLayout.barHeight

        ZStack(alignment: .top) {
            if isVisible {
                if isExpanded {
                    expandedIslandCard(width: cardWidth)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    compactContent(for: activeLayout)
                        .frame(width: activeLayout.contentWidth, height: activeLayout.barHeight)
                        .background(settings.notchBadgeMatchesBar ? BarTheme.surface : Color.black)
                        .clipShape(BottomRoundedRectangle(radius: activeLayout.hasNotch ? 12 : 14))
                        .overlay(
                            BottomRoundedRectangle(radius: activeLayout.hasNotch ? 12 : 14)
                                .stroke(isHovering ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(isHovering ? 0.55 : 0.35), radius: isHovering ? 6 : 4, y: 2)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHovering = hovering
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isExpanded = true
                                onExpandChange?(true)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(width: activeWidth, height: activeHeight + NotchLayout.bottomPadding, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: nowPlaying.isPlaying)
        .onChange(of: isVisible) { visible in
            if !visible && isExpanded {
                isExpanded = false
                onExpandChange?(false)
            }
        }
    }

    // MARK: - Compact Content

    @ViewBuilder
    private func compactContent(for activeLayout: NotchLayout) -> some View {
        if activeLayout.hasNotch {
            if nowPlaying.hasPlayer {
                HStack(spacing: 0) {
                    compactLeftInfo
                        .frame(width: activeLayout.wingWidth)
                    Color.clear
                        .frame(width: activeLayout.notchWidth)
                    compactRightInfo
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
                    compactLeftInfo
                    Spacer(minLength: 0)
                    compactRightInfo
                }
                .padding(.horizontal, 10)
            } else {
                idleNotchContent
            }
        }
    }

    private var compactLeftInfo: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(sourceAccentColor)
                    .frame(width: 17, height: 17)
                Text(sourceIconText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.black)
            }

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
        .padding(.leading, 8)
        .padding(.trailing, 4)
    }

    private var compactRightInfo: some View {
        HStack(spacing: 6) {
            Text(nowPlaying.sourceDisplayName.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)

            if nowPlaying.isPlaying {
                WaveformBars(color: sourceAccentColor)
                    .frame(width: 15, height: 12)
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.trailing, 10)
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

    private func expandedIslandCard(width: CGFloat) -> some View {
        VStack(spacing: 12) {
            // Header: Source Badge + App Selector Pills + Close
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(sourceAccentColor)
                        .frame(width: 7, height: 7)
                    Text("\(nowPlaying.sourceDisplayName) Audio Stream")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: Self.sourceBadgeMaxWidth, minHeight: 22, maxHeight: 22, alignment: .leading)
                .background(Color.white.opacity(0.08), in: Capsule())

                Spacer()

                // Multi-app selector pills
                HStack(spacing: 5) {
                    ForEach(nowPlaying.detectedSources.prefix(3)) { source in
                        Button {
                            nowPlaying.openSource(source.id)
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isExpanded = false
                            onExpandChange?(false)
                        }
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

                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.trackTitle.isEmpty ? nowPlaying.sourceDisplayName : nowPlaying.trackTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(nowPlaying.artistName.isEmpty ? "Active Audio Output" : nowPlaying.artistName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)

                    Text("CoreAudio Stream · \(nowPlaying.sourceDisplayName)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(sourceAccentColor)
                }

                Spacer(minLength: 0)
            }

            // Bottom: Controls + Scrubber
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

                // Playback state. The service exposes no position or duration, so no scrubber is shown.
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

                if let error = nowPlaying.lastCommandError {
                    Text(error)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(width: width, height: 180)
        .background(Color.black.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.8), radius: 24, y: 10)
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
