import SwiftUI

// MARK: - SettingsView

/// Settings window: a System Settings style sidebar. Displays holds every bar and notch setting,
/// per display; App holds settings that apply to all displays.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selection: SettingsPane = .barAndNotch
    @State private var barScope: SettingsScope = .defaults
    @State private var barTab: SettingsTab = .bar

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsPane.Group.allCases, id: \.self) { group in
                    Section(group.title) {
                        ForEach(SettingsPane.allCases.filter { $0.group == group }) { pane in
                            Label {
                                Text(pane.title)
                            } icon: {
                                PaneIcon(systemImage: pane.icon, tint: pane.tint)
                            }
                            .tag(pane)
                        }
                    }
                }
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
                .navigationSubtitle(selection.group == .app ? "Applies to all displays" : "")
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear { settings.reconcileWidgets() }
    }

    @ViewBuilder
    private var pane: some View {
        switch selection {
        case .barAndNotch:
            BarAndNotchPane(scope: $barScope, tab: $barTab) { selection = .general }
        case .general: GeneralPane()
        case .clock: ClockPane()
        case .tailscale:
            TailscalePane {
                barTab = .widgets
                selection = .barAndNotch
            }
        case .permissions: PermissionsPane()
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
    case barAndNotch, general, clock, tailscale, permissions

    /// Sidebar groups: per-display settings, then settings that apply to all displays.
    enum Group: CaseIterable {
        case displays, app
        var title: String { self == .displays ? "Displays" : "App" }
    }

    var id: String { rawValue }

    var group: Group { self == .barAndNotch ? .displays : .app }

    var title: String {
        switch self {
        case .barAndNotch: return "Bar & Notch"
        case .general: return "General"
        case .clock: return "Clock"
        case .tailscale: return "Tailscale"
        case .permissions: return "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .barAndNotch: return "menubar.rectangle"
        case .general: return "gearshape.fill"
        case .clock: return "clock.fill"
        case .tailscale: return "lock.shield.fill"
        case .permissions: return "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .barAndNotch: return .pink
        case .general: return .gray
        case .clock: return .orange
        case .tailscale: return .teal
        case .permissions: return .blue
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

/// The update state and its one action: check, or update to the new version.
private struct UpdateStatusRow: View {
    @ObservedObject var updates: UpdateService

    var body: some View {
        HStack(spacing: 10) {
            status
            Spacer(minLength: 12)
            switch updates.state {
            case .available(let release):
                Button("Update to v\(release.version.description)") { updates.install(release) }
                    .buttonStyle(.borderedProminent)
            case .checking, .installing:
                ProgressView().controlSize(.small)
            default:
                Button("Check Now") { updates.check() }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch updates.state {
        case .idle:
            Text(lastChecked)
        case .checking:
            Text("Checking for updates…")
        case .upToDate:
            Label("SmartWindow is up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release):
            VStack(alignment: .leading, spacing: 2) {
                Label("Version \(release.version.description) is available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Link("What's new", destination: release.pageURL).font(.caption)
            }
        case .installing(let release):
            Text("Installing v\(release.version.description)… SmartWindow reopens when it is done.")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lastChecked: String {
        guard let date = updates.lastCheck else { return "Not checked yet" }
        return "Last checked " + date.formatted(.relative(presentation: .named))
    }
}

private struct GeneralPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var login = LoginItemService.shared
    @ObservedObject private var focusMode = FocusMode.shared
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { login.isEnabled }, set: login.setEnabled))
                    .disabled(login.status == .unavailable)
                if login.status == .requiresApproval {
                    Label("Approval required in macOS", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Open Login Items Settings…", action: login.openLoginSettings)
                }
                if let message = login.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text(login.status == .unavailable
                     ? "Launch at login is available in the installed app bundle, not the development executable."
                     : "Managed by macOS Login Items. Changes outside SmartWindow are reflected here.")
            }

            Section {
                Toggle("Focus mode", isOn: $focusMode.isEnabled)
                Picker("Temperature unit", selection: $settings.temperatureUnit) {
                    Text("Celsius").tag("C")
                    Text("Fahrenheit").tag("F")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Behavior")
            } footer: {
                Text("Focus mode hides secondary widgets on all displays, keeping windows, clock and music. Use the moon in the bar to toggle it without opening Settings.")
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
                if let reason = updates.unsupportedReason {
                    Text(reason).foregroundStyle(.secondary)
                } else {
                    Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                    UpdateStatusRow(updates: updates)
                }
            } header: {
                Text("About")
            } footer: {
                Text("Permissions the app needs are in Settings → Permissions.")
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
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


// MARK: - Tailscale

/// Tailscale status only; the widget is shown or hidden in Bar & Notch › Widgets.
private struct TailscalePane: View {
    @ObservedObject private var service = TailscaleService.shared
    /// Opens Bar & Notch › Widgets.
    let showWidgets: () -> Void

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
                Text("Tailscale creates encrypted connections between your devices. A connected tailnet does not mean all internet traffic uses a VPN; that requires a configured exit node. SmartWindow never changes your VPN settings. Observed online measures how long SmartWindow has continuously seen Tailscale online, not the tunnel's age; it resets after disconnection, unavailable status, sleep, or restarting SmartWindow, and changes between five-second checks may be missed.")
            }

            Section {
                LabeledContent("Status only. To show the Tailscale VPN widget in the bar, use Bar & Notch › Widgets.") {
                    Button("Open Widgets", action: showWidgets)
                }
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
