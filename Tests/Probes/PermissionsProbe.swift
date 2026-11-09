import Foundation

// Settings → Permissions: which permissions the app needs, which are required, and how their state reads.
@main
struct PermissionsProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() {
        check(AppPermission.allCases == [.accessibility, .automationSpotify, .automationMusic, .fullDiskAccess, .focusStatus,
                                        .bluetooth],
              "lists every permission the app uses, required first")
        check(AppPermission.allCases.filter(\.isRequired) == [.accessibility], "only Accessibility is required")
        check(AppPermission.required == [.accessibility] && AppPermission.optional.count == 5, "grouped by requirement")

        let prefix = "x-apple.systempreferences:com.apple.preference.security?"
        check(AppPermission.accessibility.settingsURL.absoluteString == prefix + "Privacy_Accessibility", "Accessibility pane")
        check(AppPermission.automationSpotify.settingsURL.absoluteString == prefix + "Privacy_Automation", "Automation pane")
        check(AppPermission.automationMusic.settingsURL.absoluteString == prefix + "Privacy_Automation", "Automation pane")
        check(AppPermission.fullDiskAccess.settingsURL == FocusDatabase.fullDiskAccessSettingsURL, "Full Disk Access pane")
        check(AppPermission.focusStatus.settingsURL.absoluteString == prefix + "Privacy_Focus", "Focus pane")
        check(AppPermission.bluetooth.settingsURL.absoluteString == prefix + "Privacy_Bluetooth", "Bluetooth pane")
        check(AppPermission.automationSpotify.automationTarget == "com.spotify.client", "Spotify bundle")
        check(AppPermission.automationMusic.automationTarget == "com.apple.Music", "Music bundle")
        check(AppPermission.accessibility.automationTarget == nil, "no target for other permissions")
        for permission in AppPermission.allCases {
            check(!permission.title.isEmpty && !permission.purpose.isEmpty, "\(permission) explains what it is for")
        }

        // Apple Events permission results (AEDeterminePermissionToAutomateTarget).
        check(PermissionStatus(automationResult: 0) == .granted, "noErr is granted")
        check(PermissionStatus(automationResult: -1743) == .denied, "errAEEventNotPermitted is denied")
        check(PermissionStatus(automationResult: -1744) == .notDetermined, "errAEEventWouldRequireUserConsent asks")
        check(PermissionStatus(automationResult: -600) == .appNotRunning, "procNotFound needs the app open")
        check(PermissionStatus(automationResult: -1) == .unknown, "anything else is unknown")

        // Bluetooth (CBManager.authorization); without a usage description it is never read or asked.
        check(BluetoothAccess.status(infoDictionary: [:]) == .unknown, "no usage description: unavailable")
        check(PermissionStatus(bluetoothAuthorization: .allowedAlways) == .granted, "allowed is granted")
        check(PermissionStatus(bluetoothAuthorization: .notDetermined) == .notDetermined, "not asked yet")
        check(PermissionStatus(bluetoothAuthorization: .denied) == .denied, "denied")
        check(PermissionStatus(bluetoothAuthorization: .restricted) == .denied, "restricted reads as not granted")

        check(PermissionStatus.granted.isGranted && !PermissionStatus.denied.isGranted, "isGranted")
        check(PermissionStatus.notDetermined.canRequestInApp && !PermissionStatus.denied.canRequestInApp,
              "only an undecided permission is asked in the app; a denied one goes to System Settings")

        print("PASS: PermissionsProbe verified")
    }
}
