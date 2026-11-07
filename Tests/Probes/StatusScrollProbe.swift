import AppKit
import SwiftUI

@main
struct StatusScrollProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var windows: [NSWindow] = []

        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        func makeRow(contentWidth: CGFloat) -> NSView {
            let host = NSHostingView(rootView:
                TrailingStatusScrollView(availableWidth: 240) {
                    HStack(spacing: 0) {
                        Color.blue.frame(width: contentWidth - 80, height: 24)
                        Text("12:34 PM").frame(width: 80, height: 24)
                    }
                }
                .frame(width: 240, height: 34)
            )
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 34),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            windows.append(window)
            host.layoutSubtreeIfNeeded()
            settle()
            return host
        }

        let overflowing = makeRow(contentWidth: 600)
        guard let scroll = scrollView(in: overflowing), let document = scroll.documentView else {
            fputs("FAIL: horizontal status scroll view was not mounted\n", stderr)
            exit(1)
        }
        check(scroll.contentView.bounds.width <= 240, "viewport stays within the available width")
        check(document.bounds.width >= 600, "overflowing widgets are not compressed")
        check(abs(scroll.documentVisibleRect.maxX - document.bounds.maxX) < 1,
              "initial viewport shows the rightmost clock completely")
        scroll.contentView.scroll(to: CGPoint(x: 0, y: scroll.contentView.bounds.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        check(abs(scroll.documentVisibleRect.minX) < 1, "leftmost widgets remain reachable by scrolling")
        settle()
        check(abs(scroll.documentVisibleRect.minX) < 1, "layout does not reset a manual scroll")

        let short = makeRow(contentWidth: 120)
        guard let shortScroll = scrollView(in: short), let shortDocument = shortScroll.documentView else {
            fputs("FAIL: short status row was not mounted\n", stderr)
            exit(1)
        }
        check(shortDocument.bounds.width <= 240, "a short row creates no overflow")
        check(abs(shortScroll.documentVisibleRect.maxX - shortDocument.bounds.maxX) < 1,
              "a short row stays right-aligned")
        print("PASS: StatusScrollProbe verified")
        _ = windows
        exit(0)
    }
}
