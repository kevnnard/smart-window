import SwiftUI

// MARK: - SettingsView

/// Settings window: a System Settings style sidebar with one pane per area.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(systemImage: pane.icon, tint: pane.tint)
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 2) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    Text("SmartWindow")
                        .font(.system(size: 12, weight: .semibold))
                    Text(Self.versionString)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        } detail: {
            pane
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear { settings.reconcileWidgets() }
    }

    @ViewBuilder
    private var pane: some View {
        switch selection {
        case .general: GeneralPane()
        case .appearance: AppearancePane()
        case .widgets: WidgetsPane()
        case .clock: ClockPane()
        case .tailscale: TailscalePane()
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }
}

// MARK: - Panes

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, widgets, clock, tailscale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .widgets: return "Widgets"
        case .clock: return "Clock"
        case .tailscale: return "Tailscale"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .widgets: return "square.grid.3x1.below.line.grid.1x2.fill"
        case .clock: return "clock.fill"
        case .tailscale: return "lock.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .pink
        case .widgets: return .blue
        case .clock: return .orange
        case .tailscale: return .teal
        }
    }
}

/// Rounded colored square icon, as in System Settings.
private struct PaneIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("Startup")
            }

            Section {
                ShortcutRow(label: "Show or hide the bar", keys: ["⌥", "esc"])
                ShortcutRow(label: "Next window", keys: ["⌥", "]"])
                ShortcutRow(label: "Previous window", keys: ["⌥", "["])
                ShortcutRow(label: "Jump to tab 1 to 9", keys: ["⌥", "1…9"])
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Shortcuts are global and work in any app.")
            }

            Section {
                LabeledContent("Version", value: SettingsView.versionString)
                LabeledContent("Accessibility") {
                    PermissionBadge(granted: AccessibilityService.shared.isAccessibilityEnabled)
                }
            } header: {
                Text("About")
            } footer: {
                Text("Accessibility access is required to list and switch windows.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let label: String
    let keys: [String]

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.primary.opacity(0.12)))
                }
            }
        }
    }
}

private struct PermissionBadge: View {
    let granted: Bool

    var body: some View {
        Label(granted ? "Granted" : "Not granted", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(granted ? Color.green : Color.orange)
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Bar opacity") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.barOpacity, in: 0.6...1.0, step: 0.02)
                            .frame(width: 180)
                        Text("\(Int((settings.barOpacity * 100).rounded()))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Bar")
            } footer: {
                Text("Lower opacity lets the wallpaper show through the bar.")
            }

            Section {
                Picker("Now Playing badge", selection: $settings.notchBadgeMatchesBar) {
                    Text("Black").tag(false)
                    Text("Match bar color").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Notch")
            } footer: {
                Text("Black blends with the physical notch on MacBook screens.")
            }

            Section {
                BarPreview()
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
    }
}

/// Small live preview of the bar and the notch badge with the current appearance settings.
private struct BarPreview: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.teal, .indigo], startPoint: .leading, endPoint: .trailing)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    previewTab("1 · Finder", active: false)
                    previewTab("2 · Safari", active: true)
                    Spacer()
                    previewBadge("CPU 12%", color: BarTheme.badgeCpu)
                    previewBadge("RAM 48%", color: BarTheme.badgeRam)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(BarTheme.surface.opacity(settings.barOpacity))

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.2)).frame(width: 14, height: 14)
                    Text("Track · Artist")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "waveform").font(.system(size: 9)).foregroundStyle(BarTheme.badgeMusic)
                }
                .padding(.horizontal, 8)
                .frame(width: 150, height: 22)
                .background(settings.notchBadgeMatchesBar ? BarTheme.surface : Color.black)
                .clipShape(BottomRoundedRectangle(radius: 7))
            }
        }
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func previewTab(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(active ? BarTheme.activeText : BarTheme.inactiveText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(active ? BarTheme.activeTab : BarTheme.tabBackground, in: RoundedRectangle(cornerRadius: 4))
    }

    private func previewBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Widgets

private struct WidgetsPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(settings.widgetOrder, id: \.self) { id in
                        WidgetRow(id: id, isLast: id == settings.widgetOrder.last)
                    }
                    .onMove { from, to in
                        settings.widgetOrder.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(height: CGFloat(settings.widgetOrder.count) * 30 + 12)
                .scrollDisabled(true)
            } header: {
                Text("Bar widgets")
            } footer: {
                Text("Drag to reorder. The clock always stays at the far right. Keyboard input uses your enabled macOS keyboard sources, not the app language.")
            }

            Section {
                Picker("Temperature unit", selection: $settings.temperatureUnit) {
                    Text("Celsius").tag("C")
                    Text("Fahrenheit").tag("F")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Units")
            }
        }
        .formStyle(.grouped)
    }
}

private struct WidgetRow: View {
    @ObservedObject private var settings = AppSettings.shared
    let id: String
    let isLast: Bool

    private var isVisible: Binding<Bool> {
        Binding(
            get: { settings.widgetVisibility[id] ?? true },
            set: { settings.widgetVisibility[id] = $0 }
        )
    }

    private var hasSeparator: Binding<Bool> {
        Binding(
            get: { settings.separatorPositions.contains(id) },
            set: { on in
                if on {
                    if !settings.separatorPositions.contains(id) { settings.separatorPositions.append(id) }
                } else {
                    settings.separatorPositions.removeAll { $0 == id }
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Text(AppSettings.widgetDisplayName(id))
                .foregroundStyle(isVisible.wrappedValue ? .primary : .secondary)
            Spacer()
            Toggle("Separator after", isOn: hasSeparator)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(isLast)
                .help(isLast ? "The last widget always has a separator" : "Draw a divider after this widget")
            Toggle("Visible", isOn: isVisible)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tailscale

private struct TailscalePane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var service = TailscaleService.shared

    private var status: String {
        switch service.state {
        case .notInstalled: return "Not installed"
        case .unavailable: return "Status unavailable"
        case .stopped: return "Off or awaiting authorization"
        case .connecting: return "Connecting"
        case .connected: return "Connected to your tailnet"
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Tailscale", value: status)
                if service.isConnected {
                    if !service.tailnetName.isEmpty {
                        LabeledContent("Tailnet", value: service.tailnetName)
                    }
                    if !service.tailscaleIP.isEmpty {
                        LabeledContent("Tailscale IP", value: service.tailscaleIP)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LabeledContent("Observed online", value: service.connectedDuration(now: context.date) ?? "--")
                    }
                }
                if service.state == .notInstalled {
                    Link("Get Tailscale…", destination: TailscaleService.downloadURL)
                } else {
                    Button("Open Tailscale") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macsys")
                            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macos") {
                            NSWorkspace.shared.open(url)
                        } else {
                            NSWorkspace.shared.open(TailscaleService.downloadURL)
                        }
                    }
                }
            } header: {
                Text("Private network")
            } footer: {
                Text("Tailscale creates encrypted connections between your devices. A connected tailnet does not mean all internet traffic uses a VPN; that requires a configured exit node. SmartWindow never changes your VPN settings.")
            }

            Section {
                Toggle("Show Tailscale widget", isOn: Binding(
                    get: { settings.widgetVisibility["Tailscale"] ?? false },
                    set: { settings.widgetVisibility["Tailscale"] = $0 }
                ))
            } header: {
                Text("Menu bar")
            } footer: {
                Text("Hidden when Tailscale is not installed. The timer measures how long SmartWindow has continuously observed Tailscale online, not the actual tunnel connection age. It resets after disconnection, unavailable status, sleep, or restarting SmartWindow. Changes between five-second checks may be missed.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Clock

private struct ClockPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var search = ""

    private var matches: [String] {
        guard !search.isEmpty else { return [] }
        let query = search.lowercased().replacingOccurrences(of: " ", with: "_")
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.lowercased().contains(query) && !settings.extraTimezones.contains($0) }
            .sorted()
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        Form {
            Section {
                Picker("Shown in the bar", selection: $settings.previewTimezone) {
                    Text("Local time").tag("")
                    ForEach(settings.extraTimezones, id: \.self) { tz in
                        Text(Self.cityName(tz)).tag(tz)
                    }
                }
            } header: {
                Text("Clock")
            } footer: {
                Text("Click the clock in the bar to switch between these timezones.")
            }

            Section {
                if settings.extraTimezones.isEmpty {
                    Text("No extra timezones yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.extraTimezones, id: \.self) { tz in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.cityName(tz))
                            Text(tz)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Self.currentTime(in: tz))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            settings.extraTimezones.removeAll { $0 == tz }
                            if settings.previewTimezone == tz { settings.previewTimezone = "" }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }

                TextField("Add a city or region, e.g. Madrid", text: $search)
                    .textFieldStyle(.roundedBorder)
                ForEach(matches, id: \.self) { tz in
                    Button {
                        settings.extraTimezones.append(tz)
                        search = ""
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text(Self.cityName(tz))
                            Spacer()
                            Text(tz).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Extra timezones")
            }
        }
        .formStyle(.grouped)
    }

    static func cityName(_ identifier: String) -> String {
        (identifier.components(separatedBy: "/").last ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    static func currentTime(in identifier: String) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return "" }
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: Date())
    }
}
