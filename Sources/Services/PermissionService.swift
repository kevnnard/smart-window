import AppKit
import ApplicationServices
import Intents

/// Reads and requests the permissions listed in Settings → Permissions.
@MainActor
final class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published private(set) var statuses: [AppPermission: PermissionStatus] = [:]

    private init() {
        refresh()
    }

    func status(of permission: AppPermission) -> PermissionStatus {
        statuses[permission] ?? .unknown
    }

    /// Whether every required permission is granted.
    var hasRequiredPermissions: Bool {
        AppPermission.required.allSatisfy { status(of: $0).isGranted }
    }

    func refresh() {
        statuses[.accessibility] = AXIsProcessTrusted() ? .granted : .denied
        statuses[.fullDiskAccess] = FocusDatabase.canRead() ? .granted : .denied
        statuses[.focusStatus] = focusStatus()
        for permission in AppPermission.allCases {
            guard let target = permission.automationTarget else { continue }
            Task.detached {
                let status = Self.automationStatus(of: target, ask: false)
                await MainActor.run { self.statuses[permission] = status }
            }
        }
    }

    /// Shows the macOS prompt when it can; otherwise opens the right System Settings pane.
    func request(_ permission: AppPermission) {
        switch permission {
        case .accessibility:
            // Adds SmartWindow to the list and shows the system prompt that leads to System Settings.
            AccessibilityService.shared.requestAccessibilityPermission()
            NSWorkspace.shared.open(permission.settingsURL)
        case .focusStatus where status(of: permission).canRequestInApp:
            INFocusStatusCenter.default.requestAuthorization { _ in
                Task { @MainActor in self.refresh() }
            }
        case .automationSpotify, .automationMusic:
            guard let target = permission.automationTarget, status(of: permission).canRequestInApp else {
                NSWorkspace.shared.open(permission.settingsURL)
                return
            }
            // The prompt blocks until answered, so it runs off the main thread.
            Task.detached {
                let status = Self.automationStatus(of: target, ask: true)
                await MainActor.run { self.statuses[permission] = status }
            }
        default:
            NSWorkspace.shared.open(permission.settingsURL)
        }
    }

    private func focusStatus() -> PermissionStatus {
        // Without a usage description (a build without Info.plist) asking would terminate the app.
        guard Bundle.main.object(forInfoDictionaryKey: "NSFocusStatusUsageDescription") != nil else { return .unknown }
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .unknown
        }
    }

    nonisolated private static func automationStatus(of bundleIdentifier: String, ask: Bool) -> PermissionStatus {
        // With the target closed, the check blocks for a long time instead of returning procNotFound.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
            return .appNotRunning
        }
        var target = AEAddressDesc()
        let bytes = Array(bundleIdentifier.utf8)
        let created = bytes.withUnsafeBytes {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &target)
        }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        let result = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard),
                                                           AEEventID(typeWildCard), ask)
        return PermissionStatus(automationResult: result)
    }
}
