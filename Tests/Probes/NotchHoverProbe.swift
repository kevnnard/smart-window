import AppKit
import SwiftUI

@main
struct NotchHoverProbe {
    @MainActor
    static func main() {
        let state = NotchPanelState()
        let compact = CGRect(x: 50, y: 0, width: 249, height: 38)
        let expanded = CGRect(x: 0, y: 0, width: 349, height: 218)
        let host = NotchHostingView(rootView: Color.clear, panelState: state,
                                   hoverRect: { state.isExpanded ? expanded : compact })
        host.frame = CGRect(x: 0, y: 0, width: 349, height: 224)

        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }
        func area() -> CGRect {
            host.refreshHoverArea()
            return host.trackingAreas.first(where: { $0.owner === host })!.rect
        }
        check(host.isFlipped, "hosting view uses top-left coordinates")
        check(area() == compact, "collapsed hover matches the compact row at the top")
        check(area().contains(CGPoint(x: 60, y: 10)), "compact row accepts hover")
        check(!area().contains(CGPoint(x: 60, y: 190)), "invisible drawer cannot open the compact notch")
        check(!area().contains(CGPoint(x: 20, y: 10)), "extra drawer width cannot open the compact notch")
        state.expand()
        check(area() == expanded, "expanded hover includes the visible drawer")
        check(area().contains(CGPoint(x: 60, y: 190)), "expanded drawer retains hover")
        state.collapse()
        check(area() == compact, "collapse restores compact hover bounds")
        check(!area().contains(CGPoint(x: 60, y: 190)), "collapsed drawer does not retain expanded hover")

        // The window always has the open drawer's size; its transparent part must let clicks reach
        // the window below (a browser tab under the notch area).
        let window = NotchOverlayWindow(contentRect: CGRect(x: 1000, y: 776, width: 349, height: 224),
                                        styleMask: [], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(x: 0, y: 0, width: 349, height: 224)
        check(window.ignoresMouseEvents, "a new notch window lets clicks through until the pointer is over the notch")
        // Screen coordinates: origin bottom-left; the window's top edge is at y = 1000.
        // A hidden notch (nothing playing) neither takes clicks nor opens under the pointer.
        host.updatePointer(at: CGPoint(x: 1000 + 60, y: 1000 - 10))
        check(window.ignoresMouseEvents && !state.isExpanded, "a hidden notch ignores the pointer")
        window.orderFrontRegardless()
        host.updatePointer(at: CGPoint(x: 1000 + 60, y: 1000 - 10))
        check(!window.ignoresMouseEvents, "the compact pill takes clicks")
        check(state.isExpanded, "entering the pill still opens the drawer")
        host.updatePointer(at: CGPoint(x: 1000 + 60, y: 1000 - 190))
        check(!window.ignoresMouseEvents, "the open drawer takes clicks")
        host.updatePointer(at: CGPoint(x: 1000 + 345, y: 1000 - 222))
        check(window.ignoresMouseEvents, "the transparent margin lets clicks through")
        state.collapse()
        host.updatePointer(at: CGPoint(x: 1000 + 60, y: 1000 - 190))
        check(window.ignoresMouseEvents, "where the closed drawer would be, clicks go through")
        check(!state.isExpanded, "the invisible drawer area does not open the notch")
        host.updatePointer(at: CGPoint(x: 1000 + 20, y: 1000 - 10))
        check(window.ignoresMouseEvents, "beside the closed pill, clicks go through")
        host.updatePointer(at: CGPoint(x: 500, y: 500))
        check(window.ignoresMouseEvents, "far away, clicks go through")
        print("PASS: NotchHoverProbe verified")
    }
}
