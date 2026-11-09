import SwiftUI

/// Every bar and notch setting, for Default or for one display: a display map selects the scope,
/// a live preview shows it, and the Bar · Widgets · Notch tabs edit it.
struct BarAndNotchPane: View {
    @Binding var scope: SettingsScope
    @Binding var tab: SettingsTab
    /// Opens General, where Focus mode lives.
    var openGeneral: () -> Void = {}

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var preferences = DisplayPreferences.shared
    @ObservedObject private var focusMode = FocusMode.shared
    @State private var connected = DisplayIdentity.connectedDisplays()
    @State private var previewPlaying = true

    private var known: [DisplayPreferences.KnownDisplay] { preferences.knownDisplays(connected: connected) }
    /// The scope being edited: Default whenever the map is hidden or the display is gone.
    private var editing: SettingsScope { scope.resolved(in: known) }
    private var editingDisplay: DisplayPreferences.KnownDisplay? {
        editing.key.flatMap { key in known.first { $0.key == key } }
    }
    private var base: DisplayPreferences.Settings { settings.displayDefaults(showNotch: preferences.showNowPlaying) }
    private var current: DisplayPreferences.Settings { preferences.effectiveSettings(for: editing.key, app: settings) }
    private var primaryKey: String? { NSScreen.primary.flatMap(DisplayIdentity.key(for:)) }

    var body: some View {
        Form {
            Section { scopeSection }
            Section { preview }
            Section {
                Picker("Settings", selection: $tab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tabTitle(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            switch tab {
            case .bar: barTab
            case .widgets: widgetsTab
            case .notch: notchTab
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            connected = DisplayIdentity.connectedDisplays()
        }
    }

    private func tabTitle(_ tab: SettingsTab) -> String {
        let count = editing.key.map { tab.customCount(preferences.overrides[$0]) } ?? 0
        return count > 0 ? "\(tab.title) · \(count)" : tab.title
    }

    // MARK: - Scope

    @ViewBuilder
    private var scopeSection: some View {
        if SettingsScope.showsMap(knownDisplays: known) {
            DisplayMapView(known: known, selection: editing, primaryKey: primaryKey) { scope = $0 }
            ScopeLineView(line: ScopeLine(scope: editing, known: known)) { action in
                switch action {
                case .select(let key): scope = .display(key)
                case .resetAll: if let key = editing.key { preferences.clearAll(on: key) }
                }
            }
        } else {
            let only = known.first
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(only.map { "\($0.name) is your only display. These settings apply to it directly." }
                         ?? "These settings apply to every display.")
                    Text("Connect another display to customize each one separately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "display")
            }
            if let only, only.overrideCount > 0 {
                // Settings saved while another display was connected still win over Default here.
                LabeledContent("\(only.name) keeps \(SettingsText.settings(only.overrideCount)) of its own") {
                    Button("Reset all settings for \(only.name)") { preferences.clearAll(on: only.key) }
                }
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        let display = editingDisplay
        let subtitle: String
        if !SettingsScope.showsMap(knownDisplays: known) {
            subtitle = known.first?.name ?? "All displays"
        } else if let display {
            subtitle = display.isConnected ? display.name : "\(display.name) · not connected, showing remembered settings"
        } else {
            subtitle = "Default: how a display without its own settings looks"
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Live preview").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Picker("Preview media state", selection: $previewPlaying) {
                    Text("Playing").tag(true)
                    Text("Nothing playing").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            LivePreviewView(settings: current,
                            showsCamera: display?.info?.hasCameraNotch ?? false,
                            focusMode: focusMode.isEnabled,
                            temperatureUnit: settings.temperatureUnit,
                            isPlaying: previewPlaying,
                            name: display?.name ?? "Default")
            HStack {
                Text(caption(current))
                Spacer()
                Text("Not to scale · notch at 60%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func caption(_ s: DisplayPreferences.Settings) -> String {
        let notch = s.showNotch
            ? "Notch \(SettingsText.size(s.notchSize)) · Expanded \(SettingsText.expanded(s.expandedExtraWidth)) · \(SettingsText.background(matchesBar: s.notchMatchesBar))"
            : "Notch off"
        return "Bar \(SettingsText.percent(s.barOpacity)) · \(notch)" + (focusMode.isEnabled ? " · Focus mode on" : "")
    }

    // MARK: - Bar

    @ViewBuilder
    private var barTab: some View {
        Section {
            SettingRow(title: "Bar opacity", status: status(.barOpacity, SettingsText.percent(base.barOpacity)),
                       isCustom: isCustom(.barOpacity), resetName: "Bar opacity", reset: reset(.barOpacity)) {
                ValueSlider(value: Binding(get: { current.barOpacity }, set: setBarOpacity),
                            range: DisplayPreferences.barOpacityRange, step: 0.01,
                            text: SettingsText.percent(current.barOpacity))
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Lower opacity lets the wallpaper show through the bar. Window tabs sit on the left and the clock on the far right; the clock format is in App › Clock.")
        }
    }

    // MARK: - Widgets

    @ViewBuilder
    private var widgetsTab: some View {
        if focusMode.isEnabled {
            Section {
                HStack {
                    Label("Focus mode is on, so widgets are hidden on all displays.", systemImage: "moon.fill")
                    Spacer()
                    Button("Change in General", action: openGeneral)
                }
            }
        }
        Section {
            if let orderStatus = SettingsText.orderStatus(scope: editing, isCustom: isCustom(.widgetOrder)) {
                SettingRow(title: "Widget order", status: orderStatus, isCustom: isCustom(.widgetOrder),
                           resetName: "widget order", reset: reset(.widgetOrder)) { EmptyView() }
            }
            List {
                ForEach(current.widgetOrder, id: \.self) { id in
                    widgetRow(id)
                }
                .onMove { from, to in
                    var order = current.widgetOrder
                    order.move(fromOffsets: from, toOffset: to)
                    setWidgetOrder(order)
                }
            }
            .frame(height: CGFloat(current.widgetOrder.count) * (editing.key == nil ? 30 : 44) + 12)
            .scrollDisabled(true)
        } header: {
            Text("Widgets in the bar")
        } footer: {
            Text("Drag to reorder; VoiceOver users can use the Move up and Move down actions. The clock always stays at the far right. Keyboard input uses your enabled macOS keyboard sources. The Tailscale widget is hidden when Tailscale is not installed.")
        }
    }

    private func widgetRow(_ id: String) -> some View {
        let name = AppSettings.widgetDisplayName(id)
        // The bar always draws a separator after Battery.
        let fixedSeparator = id == "Battery"
        let custom = isCustom(.widget(id)) || isCustom(.separator(id))
        let defaultText = SettingsText.widget(visible: base.isWidgetVisible(id),
                                              separator: fixedSeparator || base.hasSeparator(after: id))
        let order = current.widgetOrder
        let index = order.firstIndex(of: id) ?? 0
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(current.isWidgetVisible(id) ? .primary : .secondary)
                if let status = SettingsText.rowStatus(scope: editing, isCustom: custom, defaultValue: defaultText) {
                    StatusText(text: status, isCustom: custom)
                }
            }
            Spacer()
            Toggle("Separator after", isOn: Binding(
                get: { fixedSeparator || current.hasSeparator(after: id) },
                set: { setSeparator($0, after: id) }))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(fixedSeparator)
                .help(fixedSeparator ? "Battery always has a separator after it" : "Draw a divider after this widget")
            Toggle("Show \(name)", isOn: Binding(get: { current.isWidgetVisible(id) },
                                                 set: { setWidgetVisible($0, id) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            if editing.key != nil {
                ResetButton(name: name, action: custom ? {
                    clear(.widget(id))
                    clear(.separator(id))
                } : nil)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move up") { move(id, to: index - 1) }
        .accessibilityAction(named: "Move down") { move(id, to: index + 1) }
    }

    private func move(_ id: String, to index: Int) {
        var order = current.widgetOrder
        guard let from = order.firstIndex(of: id), order.indices.contains(index), index != from else { return }
        order.remove(at: from)
        order.insert(id, at: index)
        setWidgetOrder(order)
    }

    // MARK: - Notch

    @ViewBuilder
    private var notchTab: some View {
        let s = current
        Section {
            SettingRow(title: editing.key == nil ? "Show notch" : "Show notch on this display",
                       status: status(.showNotch, SettingsText.onOff(base.showNotch)),
                       isCustom: isCustom(.showNotch), resetName: "Show notch", reset: reset(.showNotch)) {
                Toggle("Show notch", isOn: Binding(get: { s.showNotch }, set: setShowNotch))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingRow(title: "Show when nothing is playing",
                       help: "Keeps the notch visible for the HUD and clock when no media is active.",
                       status: status(.showWhenIdle, SettingsText.onOff(base.showWhenIdle)),
                       isCustom: isCustom(.showWhenIdle), resetName: "Show when nothing is playing",
                       reset: reset(.showWhenIdle)) {
                Toggle("Show when nothing is playing", isOn: Binding(get: { s.showWhenIdle }, set: setShowWhenIdle))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingRow(title: "Background",
                       status: status(.notchBackground, SettingsText.background(matchesBar: base.notchMatchesBar)),
                       isCustom: isCustom(.notchBackground), resetName: "notch Background", reset: reset(.notchBackground)) {
                Picker("Background", selection: Binding(get: { s.notchMatchesBar }, set: setNotchMatchesBar)) {
                    Text("Black").tag(false)
                    Text("Match bar color").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        } header: {
            Text("Visibility")
        } footer: {
            Text("Black blends with the physical notch on MacBook screens.")
        }

        Section {
            SettingRow(title: "Width", status: status(.notchSize, SettingsText.points(base.notchSize.width)),
                       isCustom: isCustom(.notchSize), resetName: "notch size", reset: reset(.notchSize)) {
                ValueSlider(value: Binding(get: { s.notchSize.width },
                                           set: { setNotchSize(.init(width: $0, height: current.notchSize.height)) }),
                            range: DisplayPreferences.NotchSize.widthRange, step: 2,
                            text: SettingsText.points(s.notchSize.width))
            }
            SettingRow(title: "Height", status: status(.notchSize, SettingsText.points(base.notchSize.height)),
                       isCustom: isCustom(.notchSize), resetName: "notch size", reset: reset(.notchSize)) {
                ValueSlider(value: Binding(get: { s.notchSize.height },
                                           set: { setNotchSize(.init(width: current.notchSize.width, height: $0)) }),
                            range: DisplayPreferences.NotchSize.heightRange, step: 1,
                            text: SettingsText.points(s.notchSize.height))
            }
            SettingRow(title: "Expanded width",
                       help: "Extra width when the notch opens for media or a HUD.",
                       status: status(.expandedExtraWidth, SettingsText.expanded(base.expandedExtraWidth)),
                       isCustom: isCustom(.expandedExtraWidth), resetName: "notch Expanded width",
                       reset: reset(.expandedExtraWidth)) {
                ValueSlider(value: Binding(get: { s.expandedExtraWidth }, set: setExpandedExtraWidth),
                            range: DisplayPreferences.expandedExtraWidthRange, step: 10,
                            text: SettingsText.expanded(s.expandedExtraWidth))
            }
        } header: {
            Text("Size")
        } footer: {
            if editingDisplay?.info?.hasCameraNotch == true {
                Text("This display has a camera notch: the width includes the camera, so the notch always covers it. The smallest width hugs the camera and shows only the artwork and the playback indicator.")
                    .foregroundStyle(.primary)
            } else {
                Text("Width and height are one setting. On a MacBook the width includes the camera notch. Width 180–440 pt and height 30–46 pt keep the notch clear of the menus on a 13\" screen. Expanded width: Same keeps the open card as wide as the notch; raise it to open wider.")
            }
        }
    }

    // MARK: - Editing (display scope writes overrides; Default writes the global settings)

    private func isCustom(_ setting: DisplayPreferences.Setting) -> Bool {
        preferences.isOverridden(setting, on: editing.key)
    }

    private func status(_ setting: DisplayPreferences.Setting, _ defaultValue: String) -> String? {
        SettingsText.rowStatus(scope: editing, isCustom: isCustom(setting), defaultValue: defaultValue)
    }

    /// The reset action of a row: only a custom setting in a display scope has one.
    private func reset(_ setting: DisplayPreferences.Setting) -> (() -> Void)? {
        guard editing.key != nil, isCustom(setting) else { return nil }
        return { clear(setting) }
    }

    private func clear(_ setting: DisplayPreferences.Setting) {
        if let key = editing.key { preferences.clear(setting, on: key) }
    }

    private func setBarOpacity(_ value: Double) {
        if let key = editing.key { preferences.setBarOpacity(value, on: key) } else { settings.barOpacity = value }
    }

    private func setWidgetOrder(_ order: [String]) {
        if let key = editing.key { preferences.setWidgetOrder(order, on: key) } else { settings.widgetOrder = order }
    }

    private func setWidgetVisible(_ visible: Bool, _ id: String) {
        if let key = editing.key {
            preferences.setWidgetVisible(visible, widget: id, on: key)
        } else {
            settings.widgetVisibility[id] = visible
        }
    }

    private func setSeparator(_ on: Bool, after id: String) {
        if let key = editing.key {
            preferences.setSeparator(on, after: id, on: key)
        } else if on {
            if !settings.separatorPositions.contains(id) { settings.separatorPositions.append(id) }
        } else {
            settings.separatorPositions.removeAll { $0 == id }
        }
    }

    private func setShowNotch(_ value: Bool) {
        if let key = editing.key { preferences.setShowNotch(value, on: key) } else { preferences.showNowPlaying = value }
    }

    private func setShowWhenIdle(_ value: Bool) {
        if let key = editing.key { preferences.setShowWhenIdle(value, on: key) } else { settings.notchAlwaysVisible = value }
    }

    private func setNotchMatchesBar(_ value: Bool) {
        if let key = editing.key { preferences.setNotchMatchesBar(value, on: key) } else { settings.notchBadgeMatchesBar = value }
    }

    private func setNotchSize(_ size: DisplayPreferences.NotchSize) {
        if let key = editing.key {
            preferences.setNotchSize(size, on: key)
        } else {
            settings.notchCustomWidth = size.clamped.width
            settings.notchCustomHeight = size.clamped.height
        }
    }

    private func setExpandedExtraWidth(_ value: Double) {
        if let key = editing.key {
            preferences.setExpandedExtraWidth(value, on: key)
        } else {
            settings.notchExpandedExtraWidth = value
        }
    }
}

// MARK: - Rows

/// One setting: its control, and in a display scope whether it is Default or Custom, with a reset.
private struct SettingRow<Control: View>: View {
    let title: String
    var help: String? = nil
    let status: String?
    let isCustom: Bool
    let resetName: String
    let reset: (() -> Void)?
    @ViewBuilder let control: Control

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                control
                if status != nil { ResetButton(name: resetName, action: reset) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let help {
                    Text(help).font(.caption).foregroundStyle(.secondary)
                }
                if let status { StatusText(text: status, isCustom: isCustom) }
            }
        }
    }
}

/// "Default · 94%", or "● Custom · Default is 94%".
private struct StatusText: View {
    let text: String
    let isCustom: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isCustom {
                Circle().fill(Color.orange).frame(width: 6, height: 6).accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(isCustom ? Color.orange : Color.secondary)
    }
}

/// Returns one setting to Default; keeps its place empty when the setting already uses Default.
private struct ResetButton: View {
    let name: String
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help(SettingsText.resetLabel(name))
            .accessibilityLabel(SettingsText.resetLabel(name))
            .frame(width: 18)
        } else {
            Color.clear.frame(width: 18, height: 1).accessibilityHidden(true)
        }
    }
}

private struct ValueSlider: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let text: String

    /// Snaps to the step in the binding: a stepped Slider draws a tick mark for every step.
    private var snapped: Binding<Double> {
        Binding(get: { value.wrappedValue },
                set: { value.wrappedValue = min(max(($0 / step).rounded() * step, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: snapped, in: range)
                .frame(width: 170)
                .accessibilityValue(text)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Display map

/// Default plus one monitor per known display; arrow keys move the selection.
private struct DisplayMapView: View {
    let known: [DisplayPreferences.KnownDisplay]
    let selection: SettingsScope
    let primaryKey: String?
    let select: (SettingsScope) -> Void

    private var scopes: [SettingsScope] { [.defaults] + known.map { .display($0.key) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit settings for")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 18) {
                    MonitorCard(title: "Default", subtitle: "All displays", badge: "Base settings", isCustom: false,
                                size: DisplayMap.defaultSize, hasCameraNotch: false, isConnected: true,
                                isDefault: true, isSelected: selection == .defaults) { select(.defaults) }
                        .accessibilityLabel("Default, all displays")
                    Divider().frame(height: DisplayMap.monitorBox.height + 30)
                    ForEach(known) { display in
                        MonitorCard(title: display.name, subtitle: subtitle(display),
                                    badge: DisplayMap.badge(overrideCount: display.overrideCount),
                                    isCustom: display.overrideCount > 0,
                                    size: DisplayMap.monitorSize(for: display.info),
                                    hasCameraNotch: display.info?.hasCameraNotch ?? false,
                                    isConnected: display.isConnected, isDefault: false,
                                    isSelected: selection == .display(display.key)) { select(.display(display.key)) }
                            .accessibilityLabel(display.name)
                            .accessibilityValue(DisplayMap.accessibilityValue(display))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
        .focusable()
        .onMoveCommand { direction in
            guard let index = scopes.firstIndex(of: selection) else { return }
            switch direction {
            case .left, .up: select(scopes[(index - 1 + scopes.count) % scopes.count])
            case .right, .down: select(scopes[(index + 1) % scopes.count])
            @unknown default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit settings for")
        .accessibilityHint("Use the arrow keys to choose Default or a display.")
    }

    private func subtitle(_ display: DisplayPreferences.KnownDisplay) -> String {
        var parts: [String] = []
        if let info = display.info {
            if info.isBuiltIn { parts.append("Built-in") }
            if info.pixelWidth > 0 { parts.append("\(info.pixelWidth) × \(info.pixelHeight)") }
        }
        if display.key == primaryKey { parts.append("Main") }
        return parts.isEmpty ? "Display" : parts.joined(separator: " · ")
    }
}

private struct MonitorCard: View {
    let title: String
    let subtitle: String
    let badge: String
    let isCustom: Bool
    let size: CGSize
    let hasCameraNotch: Bool
    let isConnected: Bool
    let isDefault: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                screen
                    .padding(.bottom, 4)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !isConnected {
                    Label("Not connected", systemImage: "minus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if isCustom { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                    Text(badge)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isCustom ? Color.orange : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background((isCustom ? Color.orange : Color.secondary).opacity(0.14), in: Capsule())
            }
            .frame(width: max(size.width, 110))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack(alignment: .top) {
            if isDefault {
                shape.fill(Color.primary.opacity(0.08))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                shape.fill(LinearGradient(colors: [Color(red: 0.29, green: 0.24, blue: 0.56),
                                                   Color(red: 0.12, green: 0.37, blue: 0.55),
                                                   Color(red: 0.16, green: 0.49, blue: 0.48)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                Rectangle().fill(Color.black.opacity(0.55)).frame(height: 5)
                if hasCameraNotch {
                    BottomRoundedRectangle(radius: 3)
                        .fill(Color.black)
                        .frame(width: size.width * 0.16, height: 7)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(isConnected ? 0.18 : 0.35),
                               style: StrokeStyle(lineWidth: isSelected ? 3 : 1, dash: isConnected ? [] : [4, 3]))
        )
        .opacity(isConnected ? 1 : 0.6)
    }
}

// MARK: - Scope line

private struct ScopeLineView: View {
    enum Action {
        case select(String)
        case resetAll
    }

    let line: ScopeLine
    let perform: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(line.text)
                if let status = line.status {
                    StatusText(text: line.isCustom ? "\(status), everything else follows Default." : status,
                               isCustom: line.isCustom)
                }
                Spacer()
                if let title = line.resetTitle {
                    Button(title) { perform(.resetAll) }
                }
            }
            if !line.links.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(line.links.enumerated()), id: \.element.key) { index, link in
                        if index > 0 { Text("·").foregroundStyle(.secondary) }
                        Button(link.text) { perform(.select(link.key)) }
                            .buttonStyle(.link)
                    }
                }
                .font(.caption)
            }
            if let note = line.notConnectedNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Live preview

/// A small drawing of one scope's bar and notch, updated as its values change.
private struct LivePreviewView: View {
    let settings: DisplayPreferences.Settings
    let showsCamera: Bool
    let focusMode: Bool
    let temperatureUnit: String
    let isPlaying: Bool
    let name: String

    private let scale = LivePreview.scale
    private var barColor: Color { BarTheme.surface.opacity(settings.barOpacity) }
    private var widgets: [String] {
        focusMode ? [] : settings.widgetOrder.filter(settings.isWidgetVisible)
    }
    private var notchVisible: Bool { settings.showNotch && (isPlaying || settings.showWhenIdle) }

    var body: some View {
        let pill = LivePreview.notchSize(settings.notchSize)
        ZStack(alignment: .top) {
            LinearGradient(colors: [.teal, .indigo], startPoint: .leading, endPoint: .trailing)
            bar
            if notchVisible && settings.expandedExtraWidth > 0 {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: (CGFloat(settings.notchSize.width + settings.expandedExtraWidth)) * scale,
                           height: pill.height * 1.9)
                    .overlay(alignment: .bottom) {
                        Text("Expanded \(SettingsText.expanded(settings.expandedExtraWidth))")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.bottom, 2)
                    }
            }
            if showsCamera {
                BottomRoundedRectangle(radius: 6)
                    .fill(Color.black)
                    .frame(width: 176 * scale, height: 32 * scale)
            }
            if notchVisible {
                notch(size: pill)
            } else {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(.top, 40)
            }
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the top bar for \(name)")
        .accessibilityValue("\(widgets.count) widgets, bar opacity \(SettingsText.percent(settings.barOpacity)), "
                            + (settings.showNotch ? "notch \(Int(settings.notchSize.width)) by \(Int(settings.notchSize.height)) points"
                                                  : "notch off"))
    }

    private var message: String {
        if !settings.showNotch {
            return showsCamera ? "Notch off: only the camera housing remains" : "Notch off on this display"
        }
        return "Hidden while nothing is playing"
    }

    /// Window tabs on the left and widgets on the right, with room for the notch between them.
    private var bar: some View {
        let notchRoom = max(notchVisible ? CGFloat(settings.notchSize.width) : 0, showsCamera ? 176 : 0) * scale + 12
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                tab("Safari", active: true)
                tab("Xcode", active: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            Color.clear.frame(width: notchRoom)
            barWidgets
                .frame(maxWidth: .infinity, alignment: .trailing)
                .clipped()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(barColor)
    }

    private var barWidgets: some View {
        HStack(spacing: 6) {
            ForEach(widgets, id: \.self) { id in
                let sample = Self.sample(id, unit: temperatureUnit)
                Text(sample.text)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(sample.color)
                    .lineLimit(1)
                    .fixedSize()
                if settings.hasSeparator(after: id) || id == "Battery" {
                    Rectangle().fill(BarTheme.separator).frame(width: 1, height: 10)
                }
            }
            Text("Sun 8 Nov 9:41")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(BarTheme.badgeDate)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func tab(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(active ? BarTheme.activeText : BarTheme.inactiveText)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(active ? BarTheme.activeTab : BarTheme.tabBackground, in: RoundedRectangle(cornerRadius: 3))
    }

    private func notch(size: CGSize) -> some View {
        // On a camera notch the middle is hidden, so the title shows only on wide notches.
        let room = showsCamera ? settings.notchSize.width - 176 : settings.notchSize.width
        return HStack(spacing: 5) {
            if isPlaying && room >= 30 {
                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach([5.0, 9.0, 6.0, 8.0], id: \.self) { height in
                        RoundedRectangle(cornerRadius: 1).fill(BarTheme.badgeMusic).frame(width: 2, height: height)
                    }
                }
            }
            if room >= 150 || (!showsCamera && room >= 120) {
                Text(isPlaying ? "Midnight City" : "9:41")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(settings.notchMatchesBar ? barColor : Color.black)
        .clipShape(BottomRoundedRectangle(radius: size.height / 2))
    }

    static func sample(_ id: String, unit: String) -> (text: String, color: Color) {
        switch id {
        case "RAM": return ("RAM 62%", BarTheme.badgeRam)
        case "CPU": return ("CPU 18%", BarTheme.badgeCpu)
        case "Temperature": return (unit == "F" ? "126°F" : "52°C", BarTheme.badgeMic)
        case "GPU": return ("GPU 9%", BarTheme.badgeGpu)
        case "MIC": return ("MIC OFF", BarTheme.badgeMic)
        case "VOL": return ("VOL 60%", BarTheme.badgeVolume)
        case "Tailscale": return ("TS ON", BarTheme.badgeVpn)
        case "Keyboard": return ("ES", BarTheme.inactiveText)
        case "Battery": return ("87%", BarTheme.badgeBattery)
        default: return (id, BarTheme.inactiveText)
        }
    }
}
