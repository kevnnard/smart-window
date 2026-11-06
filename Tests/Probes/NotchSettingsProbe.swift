import Foundation

@main struct NotchSettingsProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() {
                fputs("FAIL: \(name)\n", stderr)
                exit(1)
            }
        }

        // Test constants
        check(AppSettings.notchMinWidth == 180.0, "notchMinWidth is 180")
        check(AppSettings.notchMaxWidth == 440.0, "notchMaxWidth is 440")
        check(AppSettings.notchMinHeight == 30.0, "notchMinHeight is 30")
        check(AppSettings.notchMaxHeight == 46.0, "notchMaxHeight is 46")
        check(AppSettings.notchDefaultWidth == 280.0, "notchDefaultWidth is 280")
        check(AppSettings.notchDefaultHeight == 34.0, "notchDefaultHeight is 34")

        // Test NotchLayout logic
        let nonNotchedLayout = NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 280, customHeight: 34)
        check(!nonNotchedLayout.hasNotch, "non-notched hasNotch is false")
        check(nonNotchedLayout.contentWidth == 280, "non-notched contentWidth matches customWidth")
        check(nonNotchedLayout.barHeight == 34, "non-notched barHeight matches customHeight")
        check(nonNotchedLayout.panelSize.width == 280, "panelSize width matches contentWidth")
        check(nonNotchedLayout.panelSize.height == 34 + NotchLayout.bottomPadding, "panelSize height includes bottom padding")

        // Test custom dimensions on non-notched layout
        let customNonNotched = NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 350, customHeight: 40)
        check(customNonNotched.contentWidth == 350, "custom width respected")
        check(customNonNotched.barHeight == 40, "custom height respected")

        // Test notched screen layout
        let notchedLayout = NotchLayout(notchWidth: 180, physicalBarHeight: 38, customWidth: 280, customHeight: 34)
        check(notchedLayout.hasNotch, "notched hasNotch is true")
        check(abs(notchedLayout.wingWidth - 150) < 0.01, "default wingWidth is 150")
        check(abs(notchedLayout.contentWidth - (180 + 300)) < 0.01, "default notched content width is notch + 2 * wing")
        check(notchedLayout.barHeight == 38, "notched barHeight does not shrink below physical inset (38)")

        let customNotched = NotchLayout(notchWidth: 180, physicalBarHeight: 38, customWidth: 280, customHeight: 44)
        check(customNotched.barHeight == 44, "notched barHeight expands when customHeight > physicalBarHeight")

        // Panel sizing shared by NotchView and NotchController
        check(nonNotchedLayout.panelSize(expanded: false) == nonNotchedLayout.panelSize, "compact panelSize(expanded:) matches panelSize")
        let expandedSmall = nonNotchedLayout.panelSize(expanded: true)
        check(expandedSmall.width == 440, "expanded width is at least 440")
        check(expandedSmall.height == NotchLayout.expandedCardHeight + NotchLayout.bottomPadding, "expanded height is card height plus bottom padding")
        check(NotchLayout.expandedCardHeight == 180, "expanded card height is 180")
        let wide = NotchLayout(notchWidth: 200, physicalBarHeight: 38, customWidth: 440, customHeight: 34)
        check(wide.contentWidth > 440, "wide layout content is wider than 440")
        check(wide.panelSize(expanded: true).width == wide.contentWidth, "expanded width never below contentWidth")
        check(wide.panelSize(expanded: true).width >= wide.panelSize(expanded: false).width, "expanded never narrower than compact")

        // Visible source badges always include the main source
        func source(_ id: String, active: Bool = false) -> AudioSourceInfo {
            AudioSourceInfo(id: id, name: id, category: "media", icon: nil, isActive: active)
        }
        let few = [source("a", active: true), source("b"), source("c")]
        check(NotchView.visibleSources(few, max: 3).map(\.id) == ["a", "b", "c"], "list of 3 unchanged")
        let two = [source("a"), source("b", active: true)]
        check(NotchView.visibleSources(two, max: 3).map(\.id) == ["a", "b"], "list of 2 unchanged")
        let inside = [source("a"), source("b", active: true), source("c"), source("d")]
        check(NotchView.visibleSources(inside, max: 3).map(\.id) == ["a", "b", "c"], "active within first 3 keeps order")
        let beyond = [source("a"), source("b"), source("c"), source("d", active: true), source("e")]
        let visible = NotchView.visibleSources(beyond, max: 3).map(\.id)
        check(visible == ["d", "a", "b"], "active beyond index 2 is moved first into the visible set")
        check(visible.count == 3, "visible set never exceeds max")
        let noneActive = [source("a"), source("b"), source("c"), source("d")]
        check(NotchView.visibleSources(noneActive, max: 3).map(\.id) == ["a", "b", "c"], "no active source keeps first 3")

        print("PASS: NotchSettingsProbe verified")
    }
}
