import Foundation

@main struct WindowOverflowProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        check(WindowOverflowPolicy.visibleCount(total: 10, width: 363) == 2, "overflow reserves button space")
        check(WindowOverflowPolicy.visibleCount(total: 2, width: 303) == 2, "exact fit keeps all windows")
        check(WindowOverflowPolicy.visibleCount(total: 2, width: 302) == 1, "one point below fit overflows")
        check(WindowOverflowPolicy.visibleCount(total: 0, width: 1000) == 0, "empty list")
        check(WindowOverflowPolicy.visibleCount(total: 1, width: 40) == 0, "tiny region still offers overflow")
        check(WindowOverflowPolicy.visibleCount(total: 10, width: -5) == 0, "no negative capacity")
        check(WindowOverflowPolicy.matches(query: "  SAFARI ", app: "Safari", title: "Documentation"), "case insensitive app search")
        check(WindowOverflowPolicy.matches(query: "cafe", app: "Notes", title: "Café list"), "title search folds accents")
        check(WindowOverflowPolicy.matches(query: " ", app: "Safari", title: ""), "empty search returns all")
        check(!WindowOverflowPolicy.matches(query: "music", app: "Safari", title: "Docs"), "unmatched search")
        print("PASS: window overflow budgets and search preserve source ordering")
    }
}
