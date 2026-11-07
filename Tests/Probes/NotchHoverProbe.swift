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
        print("PASS: NotchHoverProbe verified")
    }
}
