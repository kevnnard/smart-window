import SwiftUI

// MARK: - NotchLayout

/// Geometry of the notch badge for one screen.
struct NotchLayout: Equatable {
    /// Width of the physical notch (0 on screens without one).
    let notchWidth: CGFloat
    /// Height of the black bar (matches the menu bar on notched screens).
    let barHeight: CGFloat
    /// Content width on each side of the notch (notched screens) or total pill width.
    static let wingWidth: CGFloat = 150
    static let pillWidth: CGFloat = 280
    static let bottomPadding: CGFloat = 6

    var hasNotch: Bool { notchWidth > 0 }

    var contentWidth: CGFloat {
        hasNotch ? notchWidth + Self.wingWidth * 2 : Self.pillWidth
    }

    var panelSize: CGSize {
        CGSize(width: contentWidth, height: barHeight + Self.bottomPadding)
    }

    static func forScreen(_ screen: NSScreen) -> NotchLayout {
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return NotchLayout(notchWidth: 0, barHeight: 34)
        }
        let notch = screen.frame.width - left.width - right.width
        return NotchLayout(notchWidth: max(0, notch.rounded()), barHeight: inset)
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
/// Visible while a supported player is running; hides only when the player quits.
struct NotchView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject private var settings = AppSettings.shared
    let layout: NotchLayout

    private var isVisible: Bool { nowPlaying.hasPlayer }

    var body: some View {
        ZStack(alignment: .top) {
            if isVisible {
                content
                    .frame(width: layout.contentWidth, height: layout.barHeight)
                    .background(settings.notchBadgeMatchesBar ? BarTheme.surface : Color.black)
                    .clipShape(BottomRoundedRectangle(radius: layout.hasNotch ? 12 : 14))
                    .overlay(
                        BottomRoundedRectangle(radius: layout.hasNotch ? 12 : 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: nowPlaying.isPlaying)
    }

    @ViewBuilder
    private var content: some View {
        if layout.hasNotch {
            HStack(spacing: 0) {
                trackInfo
                    .frame(width: NotchLayout.wingWidth)
                Color.clear
                    .frame(width: layout.notchWidth)
                playbackIndicator
                    .frame(width: NotchLayout.wingWidth)
            }
        } else {
            HStack(spacing: 10) {
                trackInfo
                Spacer(minLength: 0)
                playbackIndicator
                    .frame(width: 36)
            }
            .padding(.horizontal, 12)
        }
    }

    private var trackInfo: some View {
        HStack(spacing: 8) {
            artwork
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(text: nowPlaying.trackTitle.isEmpty ? "Nothing playing" : nowPlaying.trackTitle,
                            font: .system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(height: 13)
                if !nowPlaying.artistName.isEmpty {
                    MarqueeText(text: nowPlaying.artistName,
                                font: .system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(height: 11)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .onTapGesture { nowPlaying.openPlayer() }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Open player")
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = nowPlaying.artwork ?? nowPlaying.playerIcon {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(0.1)
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var playbackIndicator: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if nowPlaying.isPlaying {
                WaveformBars()
                    .frame(width: 18, height: 14)
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.trailing, 14)
    }
}

// MARK: - WaveformBars

/// Four bouncing bars, animated only while shown.
struct WaveformBars: View {
    @State private var animate = false
    private let heights: [CGFloat] = [0.45, 1.0, 0.65, 0.85]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(red: 0.11, green: 0.84, blue: 0.38))
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
