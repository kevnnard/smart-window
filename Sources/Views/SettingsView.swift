import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var timezoneSearch = ""

    /// All known timezone identifiers, filtered by search text.
    private var filteredTimezones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        if timezoneSearch.isEmpty { return all }
        let query = timezoneSearch.lowercased()
        return all.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                preferencesCard
                timezonesCard
                shortcutsCard
                aboutCard
            }
            .padding(20)
        }
        .frame(width: 460, height: 520)
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

    private var timezonesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Extra Timezones")

            Text("Additional clocks shown at the end of the bar, styled subtly.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Current extra timezones
            if !settings.extraTimezones.isEmpty {
                VStack(spacing: 6) {
                    ForEach(settings.extraTimezones, id: \.self) { tz in
                        HStack {
                            Text(tz.replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 12))
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settings.extraTimezones.removeAll { $0 == tz }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Add timezone
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))

                TextField("Search timezone…", text: $timezoneSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !timezoneSearch.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredTimezones.prefix(8), id: \.self) { tz in
                            Button {
                                if !settings.extraTimezones.contains(tz) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        settings.extraTimezones.append(tz)
                                    }
                                }
                                timezoneSearch = ""
                            } label: {
                                HStack {
                                    Text(tz.replacingOccurrences(of: "_", with: " "))
                                        .font(.system(size: 12))
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.green.opacity(0.7))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)

                            if tz != filteredTimezones.prefix(8).last {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

            infoRow("Version", value: "0.1.1")
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
