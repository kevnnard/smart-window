import SwiftUI

/// Display-specific visibility layers over global widget preferences without replacing them.
struct DisplaysPane: View {
    @ObservedObject private var preferences = DisplayPreferences.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var displays: [DisplayItem] = []
    @State private var selectedDisplay = ""

    private struct DisplayItem: Identifiable {
        let id: String
        let name: String
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show Now Playing by default", isOn: $preferences.showNowPlaying)
            } header: {
                Text("All displays")
            } footer: {
                Text("Applies to displays using Default. An explicit Show or Hide below takes precedence.")
            }
            if displays.isEmpty {
                Section { Text("No display with a stable identity is available.").foregroundStyle(.secondary) }
            } else {
                Section {
                    Picker("Display", selection: $selectedDisplay) {
                        ForEach(displays) { display in
                            Text(display.name).tag(display.id)
                        }
                    }
                } footer: {
                    Text("Preferences follow the display when it reconnects. Default inherits your global settings.")
                }
                Section {
                    modePicker("Now Playing", selection: Binding(
                        get: { preferences.nowPlayingMode(on: selectedDisplay) },
                        set: { preferences.setNowPlayingMode($0, on: selectedDisplay) }))
                    ForEach(settings.widgetOrder, id: \.self) { id in
                        modePicker(AppSettings.widgetDisplayName(id), selection: Binding(
                            get: { preferences.widgetMode(id, on: selectedDisplay) },
                            set: { preferences.setWidgetMode($0, widget: id, on: selectedDisplay) }))
                    }
                } header: {
                    Text("On this display")
                } footer: {
                    Text("Widget order, separators and clock settings remain global. Show can enable a widget even when its global switch is off.")
                }
                Section {
                    Button("Use Defaults for This Display") { preferences.reset(selectedDisplay) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDisplays() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in refreshDisplays() }
    }

    private func modePicker(_ label: String, selection: Binding<DisplayPreferences.Mode>) -> some View {
        Picker(label, selection: selection) {
            ForEach(DisplayPreferences.Mode.allCases) { mode in Text(mode.label).tag(mode) }
        }
        .pickerStyle(.menu)
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
