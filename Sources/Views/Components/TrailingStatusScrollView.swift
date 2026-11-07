import SwiftUI

/// A bounded status row that starts at its right edge, keeping the clock visible.
/// Short rows stay right-aligned; overflowing widgets remain reachable by horizontal scrolling.
struct TrailingStatusScrollView<Content: View>: View {
    let availableWidth: CGFloat
    @ViewBuilder let content: () -> Content
    private let trailingID = "status-row-trailing-edge"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    content()
                        .fixedSize(horizontal: true, vertical: false)
                    Color.clear
                        .frame(width: 0, height: 1)
                        .id(trailingID)
                }
                .frame(minWidth: max(0, availableWidth), alignment: .trailing)
            }
            .frame(width: max(0, availableWidth))
            .onAppear { alignTrailing(proxy) }
            .onChange(of: availableWidth) { _ in alignTrailing(proxy) }
        }
    }

    private func alignTrailing(_ proxy: ScrollViewProxy) {
        // Wait until the measured viewport is laid out. This also supports macOS 13, where
        // defaultScrollAnchor is unavailable. Ordinary clock updates do not reset scrolling.
        DispatchQueue.main.async {
            proxy.scrollTo(trailingID, anchor: .trailing)
        }
    }
}
