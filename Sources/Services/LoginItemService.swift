import AppKit
import Combine
import ServiceManagement

/// Registration state is read from macOS, never inferred from a saved toggle.
@MainActor
final class LoginItemService: ObservableObject {
    enum Status { case enabled, disabled, requiresApproval, unavailable }
    static let shared = LoginItemService()

    @Published private(set) var status: Status = .unavailable
    @Published private(set) var errorMessage: String?
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    private let readStatus: () -> Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    convenience init() {
        self.init(status: {
            let isAppBundle = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
            return LoginItemService.status(of: SMAppService.mainApp.status, isAppBundle: isAppBundle)
        }, register: { try SMAppService.mainApp.register() },
           unregister: { try SMAppService.mainApp.unregister() },
           openSettings: { SMAppService.openSystemSettingsLoginItems() })
    }

    init(status: @escaping () -> Status, register: @escaping () throws -> Void,
         unregister: @escaping () throws -> Void, openSettings: @escaping () -> Void = {}) {
        readStatus = status
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        refresh()
    }

    /// What macOS reports, as the toggle shows it. An app bundle that was never registered gets
    /// `notFound` from macOS ("record not found"); that is off and can be turned on, not unavailable.
    /// Only a development executable (no app bundle) cannot launch at login.
    nonisolated static func status(of native: SMAppService.Status, isAppBundle: Bool) -> Status {
        guard isAppBundle else { return .unavailable }
        switch native {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    func refresh() { status = readStatus() }

    func setEnabled(_ enabled: Bool) {
        refresh()
        guard status != .unavailable else {
            errorMessage = "Install and open the SmartWindow app bundle to manage launch at login."
            return
        }
        errorMessage = nil
        do {
            if enabled {
                if !isEnabled { try register() }
            } else if isEnabled {
                try unregister()
            }
        } catch {
            errorMessage = "macOS could not update launch at login: \(error.localizedDescription)"
        }
        refresh()
        // macOS added it but wants the user to allow it: take them to Login Items.
        if enabled, status == .requiresApproval, errorMessage == nil { openSettings() }
    }

    func openLoginSettings() { openSettings() }
}
