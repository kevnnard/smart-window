import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    
    @State private var offset: CGFloat = 0
    @State private var textSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var isHovered = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .background(GeometryReader { textGeo in
                        Color.clear.onAppear {
                            textSize = textGeo.size
                        }
                        .onChange(of: text) { _ in
                            textSize = textGeo.size
                            resetAnimation()
                        }
                    })
                    .offset(x: offset)
            }
            .disabled(true) // Disable manual scrolling
            .onAppear {
                containerSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                containerSize = newSize
                resetAnimation()
            }
        }
        .clipped()
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                startAnimation()
            } else {
                resetAnimation()
            }
        }
    }
    
    private var needsScroll: Bool {
        textSize.width > containerSize.width
    }
    
    private func startAnimation() {
        guard needsScroll else { return }
        
        // Calculate the distance to scroll
        let scrollDistance = textSize.width - containerSize.width
        
        // Calculate a reasonable duration based on text length
        let duration = Double(scrollDistance) / 30.0 // 30 points per second
        
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: true)) {
            offset = -scrollDistance
        }
    }
    
    private func resetAnimation() {
        withAnimation(.linear(duration: 0.2)) {
            offset = 0
        }
        if isHovered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.isHovered {
                    self.startAnimation()
                }
            }
        }
    }
}

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

struct NotchView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @State private var isHovered = false
    
    var body: some View {
        let isVisible = nowPlaying.hasTrack || nowPlaying.isPlaying
        
        VStack(spacing: 0) {
            if isVisible {
                // Top Row: Icons positioned right next to the physical notch (~208px)
                // With 240px window width and 8px padding on each side, icons sit ~16px from notch edge
                HStack(spacing: 0) {
                    // Left: Music note icon
                    Image(systemName: "music.note")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                    
                    Spacer() // Physical notch area (~208px)
                    
                    // Right: Animated waveform or pause indicator
                    Group {
                        if nowPlaying.isPlaying {
                            if #available(macOS 14.0, *) {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeating)
                                    .foregroundColor(.white.opacity(0.8))
                                    .transition(.opacity)
                            } else {
                                Image(systemName: "waveform")
                                    .foregroundColor(.white.opacity(0.8))
                                    .transition(.opacity)
                            }
                        } else {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 10))
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 16)
                }
                .padding(.horizontal, 8)
                .frame(height: 32) // Match physical notch height (32px)
                
                // Bottom Row: Song name on hover (fits within narrow width)
                if isHovered && nowPlaying.hasTrack {
                    MarqueeText(text: nowPlaying.displayText, font: .system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .frame(height: 10)
                        .padding(.bottom, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(width: isVisible ? 240 : 0) // ~240px to hug the ~208px physical notch with icons on sides
        .background(Color.black)
        .clipShape(BottomRoundedRectangle(radius: 10))
        .opacity(isVisible ? 1 : 0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: nowPlaying.isPlaying)
        // Container matches the panel size, anchored at top center
        .frame(width: 240, height: 44, alignment: .top)
    }
}
