import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var selectedCategory: SettingsCategory? = .general
    @State private var timezoneSearch = ""

    private var filteredTimezones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        if timezoneSearch.isEmpty { return all }
        let query = timezoneSearch.lowercased().replacingOccurrences(of: " ", with: "_")
        return all.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                NavigationLink(value: category) {
                    Label(category.label, systemImage: category.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 150)
        } detail: {
            switch selectedCategory {
            case .general:
                GeneralSettingsDetailView()
            case .system:
                SystemSettingsDetailView(timezoneSearch: $timezoneSearch, filteredTimezones: filteredTimezones)
            case .layout:
                LayoutSettingsDetailView()
            case .ai:
                AISettingsDetailView()
            case nil:
                Text("Select a category")
            }
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, system, layout, ai
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .general: return "General"
        case .system: return "System"
        case .layout: return "Layout"
        case .ai: return "AI"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .system: return "cpu"
        case .layout: return "rectangle.3.group"
        case .ai: return "brain.head.profile"
        }
    }
}

struct AISettingsDetailView: View {
    var body: some View {
        VStack {
            Text("AI Settings Coming Soon")
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Subviews

struct GeneralSettingsDetailView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section(header: Label("Preferences", systemImage: "gear")) {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            
            Section(header: Label("Keyboard Shortcuts", systemImage: "keyboard")) {
                ShortcutRow(label: "Show or hide bar", shortcut: "⌥ Esc")
                ShortcutRow(label: "Next window", shortcut: "⌥ ]")
                ShortcutRow(label: "Previous window", shortcut: "⌥ [")
                ShortcutRow(label: "Jump to tab", shortcut: "⌥ 1-9")
            }
            
            Section(header: Label("About", systemImage: "info.circle")) {
                LabeledContent("Version", value: "0.2.3")
            }
        }
        .formStyle(.grouped)
    }
}

struct SystemSettingsDetailView: View {
    @ObservedObject var settings = AppSettings.shared
    @Binding var timezoneSearch: String
    let filteredTimezones: [String]
    
    var body: some View {
        Form {
            Section(header: Label("Time and Units", systemImage: "clock")) {
                Picker("Preview Timezone", selection: $settings.previewTimezone) {
                    Text("Local").tag("")
                    ForEach(settings.extraTimezones, id: \.self) { tz in
                        Text(tz.replacingOccurrences(of: "_", with: " ")).tag(tz)
                    }
                }
                
                Picker("Temperature Unit", selection: $settings.temperatureUnit) {
                    Text("Celsius").tag("C")
                    Text("Fahrenheit").tag("F")
                }
                .pickerStyle(.segmented)
            }
            
            Section(header: Label("Extra Timezones", systemImage: "globe")) {
                ForEach(settings.extraTimezones, id: \.self) { tz in
                    HStack {
                        Text(tz.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.extraTimezones.removeAll { $0 == tz }
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search timezone…", text: $timezoneSearch)
                        .textFieldStyle(.roundedBorder)
                }
                
                if !timezoneSearch.isEmpty {
                    ScrollView {
                        ForEach(filteredTimezones.prefix(5), id: \.self) { tz in
                            Button {
                                if !settings.extraTimezones.contains(tz) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        settings.extraTimezones.append(tz)
                                    }
                                }
                                timezoneSearch = ""
                            } label: {
                                Text(tz.replacingOccurrences(of: "_", with: " "))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LayoutSettingsDetailView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var draggingItem: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(settings.widgetOrder, id: \.self) { widget in
                    HStack(spacing: 16) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                        
                        Text(widget)
                            .font(.system(.body, design: .rounded, weight: .medium))
                        
                        Spacer()
                        
                        // Visibility Toggle
                        Toggle("", isOn: Binding(
                            get: { settings.widgetVisibility[widget] ?? true },
                            set: { settings.widgetVisibility[widget] = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(FuturisticToggleStyle(icon: "eye"))
                        
                        // Separator Toggle
                        Toggle("", isOn: Binding(
                            get: { settings.separatorPositions.contains(widget) },
                            set: { isOn in
                                if isOn {
                                    if !settings.separatorPositions.contains(widget) {
                                        settings.separatorPositions.append(widget)
                                    }
                                } else {
                                    settings.separatorPositions.removeAll { $0 == widget }
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(FuturisticToggleStyle(icon: "line.horizontal.3"))
                        .disabled(widget == settings.widgetOrder.last)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onDrag {
                        if widget == "Date" { return NSItemProvider() }
                        self.draggingItem = widget
                        return NSItemProvider(object: widget as NSString)
                    }
                    .onDrop(of: [.text], delegate: WidgetDropDelegate(item: widget, items: $settings.widgetOrder, draggingItem: $draggingItem))
                }
            }
            .padding(20)
        }
    }
}

private struct WidgetDropDelegate: DropDelegate {
    let item: String
    @Binding var items: [String]
    @Binding var draggingItem: String?

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem != item,
              let from = items.firstIndex(of: draggingItem),
              let to = items.firstIndex(of: item) else { return }

        if items[to] != draggingItem {
            withAnimation {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
}

private struct FuturisticToggleStyle: ToggleStyle {
    let icon: String
    
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Image(systemName: configuration.isOn ? icon : "\(icon).slash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(configuration.isOn ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutRow: View {
    let label: String
    let shortcut: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

extension Color {
    func darker() -> Color {
        return self.opacity(0.8) // Simplified
    }
}
