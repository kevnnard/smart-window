import AppKit

/// A CoreGraphics UUID follows a monitor across disconnects, unlike NSScreenNumber.
enum DisplayIdentity {
    static func key(for screen: NSScreen) -> String? {
        guard let id = displayID(of: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Name, kind and pixel size of a screen, as remembered for when it is not connected.
    static func info(for screen: NSScreen) -> DisplayPreferences.DisplayInfo {
        let id = displayID(of: screen)
        let scale = screen.backingScaleFactor
        let pixels = id.flatMap { CGDisplayCopyDisplayMode($0) }
            .map { (width: $0.pixelWidth, height: $0.pixelHeight) }
            ?? (width: Int(screen.frame.width * scale), height: Int(screen.frame.height * scale))
        return DisplayPreferences.DisplayInfo(
            name: screen.localizedName,
            isBuiltIn: id.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
            hasCameraNotch: screen.safeAreaInsets.top > 0,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height)
    }

    /// Connected displays from left to right.
    static func connectedDisplays() -> [(key: String, info: DisplayPreferences.DisplayInfo)] {
        NSScreen.screens
            .sorted { $0.frame.minX < $1.frame.minX }
            .compactMap { screen in key(for: screen).map { (key: $0, info: info(for: screen)) } }
    }

    /// Remembers every connected display so it can be listed after it is disconnected.
    static func rememberConnectedDisplays(in preferences: DisplayPreferences = .shared) {
        for display in connectedDisplays() {
            preferences.remember(display.info, for: display.key)
        }
    }

    /// Connected displays, then not-connected ones with their own settings.
    static func knownDisplays(in preferences: DisplayPreferences = .shared) -> [DisplayPreferences.KnownDisplay] {
        preferences.knownDisplays(connected: connectedDisplays())
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
