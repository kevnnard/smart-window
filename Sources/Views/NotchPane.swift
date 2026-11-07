import SwiftUI

/// Every notch setting in one place: where it shows, how it looks, the default size for all
/// displays, and the per-display overrides.
struct NotchPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var preferences = DisplayPreferences.shared
    @State private var displays: [DisplayItem] = []
    @State private var selectedDisplay = ""

    private struct DisplayItem: Identifiable {
        let id: String
        let name: String
    }

    var body: some View {
        Form {
            Section {
                Picker("Show on", selection: $settings.notchShowOnAllDisplays) {
                    Text("All displays").tag(true)
                    Text("Main display only").tag(false)
                }
                Toggle("Show on displays set to Default", isOn: $preferences.showNowPlaying)
                Toggle("Show when nothing is playing", isOn: $settings.notchAlwaysVisible)
            } header: {
                Text("Visibility")
            } footer: {
                Text("A display set to Show or Hide below ignores the Default setting.")
            }

            Section {
                Picker("Background", selection: $settings.notchBadgeMatchesBar) {
                    Text("Black").tag(false)
                    Text("Match bar color").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Style")
            } footer: {
                Text("Black blends with the physical notch on MacBook screens.")
            }

            Section {
                sizeSlider("Width", value: settings.notchCustomWidth,
                           range: AppSettings.notchMinWidth...AppSettings.notchMaxWidth, step: 2) {
                    settings.notchCustomWidth = $0
                }
                sizeSlider("Height", value: settings.notchCustomHeight,
                           range: AppSettings.notchMinHeight...AppSettings.notchMaxHeight, step: 1) {
                    settings.notchCustomHeight = $0
                }
                Button("Reset Default Size") {
                    settings.notchCustomWidth = AppSettings.notchDefaultWidth
                    settings.notchCustomHeight = AppSettings.notchDefaultHeight
                }
            } header: {
                Text("Default size")
            } footer: {
                Text("Used by every display set to Default. On a MacBook the width includes the camera notch. Width 180–440 pt and height 30–46 pt keep the notch clear of the menus on a 13\" screen.")
            }

            displaySection
        }
        .formStyle(.grouped)
        .onAppear { refreshDisplays() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshDisplays()
        }
    }

    // MARK: - Per display

    @ViewBuilder
    private var displaySection: some View {
        if displays.isEmpty {
            Section {
                Text("No display with a stable identity is available.").foregroundStyle(.secondary)
            } header: {
                Text("Per display")
            }
        } else {
            let custom = preferences.notchSize(on: selectedDisplay)
            Section {
                Picker("Display", selection: $selectedDisplay) {
                    ForEach(displays) { display in
                        Text(display.name).tag(display.id)
                    }
                }
                Picker("Notch", selection: Binding(
                    get: { preferences.nowPlayingMode(on: selectedDisplay) },
                    set: { preferences.setNowPlayingMode($0, on: selectedDisplay) })) {
                    ForEach(DisplayPreferences.Mode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                Picker("Size", selection: Binding(
                    get: { custom != nil },
                    set: { isCustom in
                        preferences.setNotchSize(isCustom ? DisplayPreferences.NotchSize(
                            width: settings.notchCustomWidth, height: settings.notchCustomHeight) : nil,
                            on: selectedDisplay)
                    })) {
                    Text("Default").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)
                if let custom {
                    sizeSlider("Width", value: custom.width, range: DisplayPreferences.NotchSize.widthRange, step: 2) {
                        preferences.setNotchSize(.init(width: $0, height: custom.height), on: selectedDisplay)
                    }
                    sizeSlider("Height", value: custom.height, range: DisplayPreferences.NotchSize.heightRange, step: 1) {
                        preferences.setNotchSize(.init(width: custom.width, height: $0), on: selectedDisplay)
                    }
                }
                Button("Use Defaults for This Display") {
                    preferences.setNowPlayingMode(.inherit, on: selectedDisplay)
                    preferences.setNotchSize(nil, on: selectedDisplay)
                }
            } header: {
                Text("Per display")
            } footer: {
                Text(custom == nil
                     ? "This display uses the default size. Choose Custom to give it its own size. Settings follow the display when it reconnects."
                     : "On a MacBook the width includes the camera notch, so the smallest value hugs it; narrow sides show only the artwork and the playback indicator.")
            }
        }
    }

    // MARK: - Helpers

    private func sizeSlider(_ label: String, value: Double, range: ClosedRange<Double>, step: Double,
                            set: @escaping (Double) -> Void) -> some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: set), in: range, step: step)
                    .frame(width: 180)
                Text("\(Int(value)) pt")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func refreshDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            guard let key = DisplayIdentity.key(for: screen) else { return nil }
            return DisplayItem(id: key, name: "\(screen.localizedName) · \(key.suffix(4))")
        }
        if !displays.contains(where: { $0.id == selectedDisplay }) {
            selectedDisplay = displays.first?.id ?? ""
        }
    }
}
