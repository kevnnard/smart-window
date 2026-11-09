import SwiftUI

/// Every macOS permission SmartWindow uses, its state, and a way to grant it.
struct PermissionsPane: View {
    @ObservedObject private var permissions = PermissionService.shared

    var body: some View {
        Form {
            Section {
                ForEach(AppPermission.required) { row($0) }
            } header: {
                Text("Required")
            } footer: {
                Text("SmartWindow needs this to work.")
            }

            Section {
                ForEach(AppPermission.optional) { row($0) }
            } header: {
                Text("Optional")
            } footer: {
                Text("Each one turns on a feature. After granting one in System Settings, reopen SmartWindow if it does not show as granted.")
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
        // Coming back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private func row(_ permission: AppPermission) -> some View {
        let status = permissions.status(of: permission)
        return HStack(spacing: 10) {
            Image(systemName: permission.symbolName)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            statusLabel(status)
            if !status.isGranted {
                Button(status.canRequestInApp ? "Allow…" : "Open Settings…") {
                    permissions.request(permission)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusLabel(_ status: PermissionStatus) -> some View {
        let (text, symbol, color): (String, String, Color) = {
            switch status {
            case .granted: return ("Granted", "checkmark.circle.fill", .green)
            case .denied: return ("Not granted", "xmark.circle.fill", .red)
            case .notDetermined: return ("Not asked", "questionmark.circle.fill", .orange)
            case .appNotRunning: return ("Open the app to check", "minus.circle.fill", .secondary)
            case .unknown: return ("Unavailable", "minus.circle.fill", .secondary)
            }
        }()
        return Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .fixedSize()
    }
}
