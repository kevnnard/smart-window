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
                notchSizeSection
                Section {
                    Button("Use Defaults for This Display") { preferences.reset(selectedDisplay) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDisplays() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in refreshDisplays() }
    }

    /// Default keeps the global size from Appearance; Custom gives this display its own size,
    /// starting from the global values.
    private var notchSizeSection: some View {
        let custom = preferences.notchSize(on: selectedDisplay)
        return Section {
            Picker("Notch size", selection: Binding(
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
        } header: {
            Text("Notch size")
        } footer: {
            Text(custom == nil
                 ? "Uses the size from Appearance. Choose Custom to give this display its own size."
                 : "On a MacBook notch the width sizes the wings around the camera; on other displays it is the badge width.")
        }
    }

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
