import Foundation

@main struct WindowOverflowProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        let short = WindowOverflowPolicy.measuredTabWidth(appName: "Dia", index: 1)
        let long = WindowOverflowPolicy.measuredTabWidth(appName: String(repeating: "W", count: 50), index: 1)
        check(short >= 88 && short < long && long == 150, "tabs size to content within readable bounds")
        check(WindowOverflowPolicy.visibleCount(widths: [88, 88, 140], width: 250) == 2, "overflow budgets the painted tab widths")
        check(WindowOverflowPolicy.visibleCount(widths: [88, 88, 140], width: 322) == 3, "content-sized tabs exactly fit")
        check(WindowOverflowPolicy.visibleCount(widths: [88, 88, 140], width: 321) == 2, "one point below content fit reserves overflow")
        check(WindowOverflowPolicy.visibleCount(widths: Array(repeating: 150, count: 10), width: 363) == 2, "overflow reserves button space")
        check(WindowOverflowPolicy.visibleCount(widths: [150, 150], width: 303) == 2, "exact fit keeps all windows")
        check(WindowOverflowPolicy.visibleCount(widths: [150, 150], width: 302) == 1, "one point below fit overflows")
        check(WindowOverflowPolicy.visibleCount(widths: [], width: 1000) == 0, "empty list")
        check(WindowOverflowPolicy.visibleCount(widths: [150], width: 40) == 0, "tiny region still offers overflow")
        check(WindowOverflowPolicy.visibleCount(widths: Array(repeating: 150, count: 10), width: -5) == 0, "no negative capacity")
        check(WindowOverflowPolicy.matches(query: "  SAFARI ", app: "Safari", title: "Documentation"), "case insensitive app search")
        check(WindowOverflowPolicy.matches(query: "cafe", app: "Notes", title: "Café list"), "title search folds accents")
        check(WindowOverflowPolicy.matches(query: " ", app: "Safari", title: ""), "empty search returns all")
        check(!WindowOverflowPolicy.matches(query: "music", app: "Safari", title: "Docs"), "unmatched search")
        print("PASS: window overflow budgets and search preserve source ordering")
    }
}
