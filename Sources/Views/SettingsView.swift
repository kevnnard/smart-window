import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                preferencesCard
                shortcutsCard
                aboutCard
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.53, blue: 0.35),
                                Color(red: 0.12, green: 0.36, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SmartWindow")
                    .font(.system(size: 20, weight: .semibold))

                Text("Polybar-style window switcher for macOS")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Quick controls, now playing, and system info across your screens.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(cardBackground)
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Preferences")

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .medium))
                    Text("Start SmartWindow automatically when you sign in.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Keyboard Shortcuts")

            shortcutRow("Show or hide bar", shortcut: "⌥ Esc")
            shortcutRow("Next window", shortcut: "⌥ ]")
            shortcutRow("Previous window", shortcut: "⌥ [")
            shortcutRow("Jump to tab", shortcut: "⌥ 1-9")
        }
        .padding(18)
        .background(cardBackground)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("About")

            infoRow("Version", value: "0.1.0")
            infoRow("Behavior", value: "Runs as a menu bar utility")
            infoRow("Permissions", value: "Accessibility")
        }
        .padding(18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.primary.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
        .font(.system(size: 12))
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}
