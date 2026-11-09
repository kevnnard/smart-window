import CoreBluetooth
import Foundation

/// A macOS permission SmartWindow uses, as listed in Settings → Permissions.
enum AppPermission: String, CaseIterable, Identifiable {
    case accessibility
    case automationSpotify
    case automationMusic
    case fullDiskAccess
    case focusStatus
    case bluetooth
    case microphone

    var id: String { rawValue }

    static var required: [AppPermission] { allCases.filter(\.isRequired) }
    static var optional: [AppPermission] { allCases.filter { !$0.isRequired } }

    /// Without it the app cannot do its main job: the tab bar needs to read and switch windows.
    var isRequired: Bool { self == .accessibility }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .automationSpotify: return "Automation: Spotify"
        case .automationMusic: return "Automation: Music"
        case .fullDiskAccess: return "Full Disk Access"
        case .focusStatus: return "Focus Status"
        case .bluetooth: return "Bluetooth"
        case .microphone: return "Microphone"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility:
            return "Reads window titles and switches between windows for the tab bar."
        case .automationSpotify:
            return "Shows and controls what Spotify is playing in the notch."
        case .automationMusic:
            return "Shows and controls what Music is playing in the notch."
        case .fullDiskAccess:
            return "Shows which Focus turned on or off. macOS keeps the Focus name in a protected folder."
        case .focusStatus:
            return "Shows that a Focus is on when Full Disk Access is not granted."
        case .bluetooth:
            return "Shows the moment any Bluetooth device connects or disconnects. Without it, some devices take up to a minute."
        case .microphone:
            return "Moves the call waveform with your voice. Only listens during a call; without it the waveform just pulses."
        }
    }

    var symbolName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .automationSpotify, .automationMusic: return "music.note"
        case .fullDiskAccess: return "externaldrive.fill"
        case .focusStatus: return "moon.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .microphone: return "mic.fill"
        }
    }

    /// Bundle identifier of the app controlled through Apple Events (Automation only).
    var automationTarget: String? {
        switch self {
        case .automationSpotify: return "com.spotify.client"
        case .automationMusic: return "com.apple.Music"
        default: return nil
        }
    }

    /// Privacy & Security pane where the user grants or revokes it.
    var settingsURL: URL {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .automationSpotify, .automationMusic: anchor = "Privacy_Automation"
        case .fullDiskAccess: return FocusDatabase.fullDiskAccessSettingsURL
        case .focusStatus: anchor = "Privacy_Focus"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        case .microphone: anchor = "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    /// Not asked yet: the app can show the macOS prompt.
    case notDetermined
    /// Automation can only be checked while the target app is open.
    case appNotRunning
    case unknown

    /// From CBManager.authorization.
    init(bluetoothAuthorization: CBManagerAuthorization) {
        switch bluetoothAuthorization {
        case .allowedAlways: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied, .restricted: self = .denied
        @unknown default: self = .unknown
        }
    }

    /// From AEDeterminePermissionToAutomateTarget.
    init(automationResult: Int32) {
        switch automationResult {
        case 0: self = .granted // noErr
        case -1743: self = .denied // errAEEventNotPermitted
        case -1744: self = .notDetermined // errAEEventWouldRequireUserConsent
        case -600: self = .appNotRunning // procNotFound
        default: self = .unknown
        }
    }

    var isGranted: Bool { self == .granted }

    /// macOS shows its prompt only once; after a denial the user changes it in System Settings.
    var canRequestInApp: Bool { self == .notDetermined }
}

/// Bluetooth permission. Reading or asking for it without the usage description terminates the app,
/// and a debug build has no Info.plist, so it is unavailable there and the device monitor polls.
enum BluetoothAccess {
    static let usageKey = "NSBluetoothAlwaysUsageDescription"

    static func status(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> PermissionStatus {
        guard infoDictionary?[usageKey] != nil else { return .unknown }
        return PermissionStatus(bluetoothAuthorization: CBManager.authorization)
    }
}
