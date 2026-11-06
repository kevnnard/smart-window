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

        // Test defaults on AppSettings.shared
        let settings = AppSettings.shared
        check(settings.notchShowOnAllDisplays == true, "notchShowOnAllDisplays defaults to true")
        check(settings.notchAlwaysVisible == true, "notchAlwaysVisible defaults to true")
        check(settings.notchCustomWidth >= AppSettings.notchMinWidth && settings.notchCustomWidth <= AppSettings.notchMaxWidth, "notchCustomWidth within bounds")
        check(settings.notchCustomHeight >= AppSettings.notchMinHeight && settings.notchCustomHeight <= AppSettings.notchMaxHeight, "notchCustomHeight within bounds")

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

        print("PASS: NotchSettingsProbe verified")
    }
}
