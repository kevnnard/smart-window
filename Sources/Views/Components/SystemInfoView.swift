import SwiftUI
import Combine

// MARK: - SystemInfoView

/// Right side of the bar: RAM, CPU, GPU, MIC, VOL, Battery, Date, extra timezones — polybar style.
struct SystemInfoView: View {
    var displayKey: String? = nil
    @ObservedObject private var displayPreferences = DisplayPreferences.shared
    @EnvironmentObject var systemMonitor: SystemMonitorService
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var tempService = TemperatureService()
    @ObservedObject private var tailscale = TailscaleService.shared
    @StateObject private var usageService = AIUsageService()

    private var activeTimezone: TimeZone {
        if settings.previewTimezone == AppSettings.localTimezoneIdentifier || settings.previewTimezone.isEmpty {
            return .current
        }
        return TimeZone(identifier: settings.previewTimezone) ?? .current
    }

    private func cityLabel(for tz: TimeZone) -> String {
        let raw = tz.identifier.components(separatedBy: "/").last ?? tz.abbreviation() ?? "?"
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    private func formattedDateTime(for tz: TimeZone) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.dateFormat = "E, MMM d h:mm a"
        return fmt.string(from: currentTime)
    }

    @State private var currentTime = Date()
    @State private var showTimezonesPopover = false
    @State private var showTokenPopover = false
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @ViewBuilder
    private func badge(for widgetId: String) -> some View {
        switch widgetId {
        case "RAM":
            InfoBadge(label: "RAM", value: "\(systemMonitor.ramUsage)%", color: BarTheme.badgeRam)
        case "CPU":
            InfoBadge(label: "CPU", value: "\(systemMonitor.cpuUsage)%", color: BarTheme.badgeCpu)
        case "Temperature":
            TemperatureBadge(service: tempService)
        /*
        case "AI Usage":
            TokenUsageBadge(usageService: usageService)
                .onTapGesture { showTokenPopover = true }
                .popover(isPresented: $showTokenPopover) {
                    TokenUsagePopover(usageService: usageService, showPopover: $showTokenPopover)
                }
        */
        case "GPU":
            InfoBadge(label: "GPU", value: "\(systemMonitor.gpuUsage)%", color: BarTheme.badgeGpu)
        case "MIC":
            InfoBadge(label: "MIC", value: systemMonitor.isMicActive ? "ON" : "OFF", color: BarTheme.badgeMic)
        case "VOL":
            VolumeBadge(
                volume: systemMonitor.volume,
                isMuted: systemMonitor.isMuted,
                deviceName: systemMonitor.outputDeviceName
            )
        case "Tailscale":
            TimelineView(.periodic(from: .now, by: 1)) { context in
                TailscaleBadge(service: tailscale, now: context.date)
            }
        case "Keyboard":
            KeyboardInputBadge()
        case "Battery":
            BatteryBadge(level: systemMonitor.batteryLevel, isCharging: systemMonitor.isCharging)
        default:
            EmptyView()
        }
    }

    var body: some View {
        HStack(spacing: 8) { // Consistent spacing
            ForEach(settings.widgetOrder, id: \.self) { widgetId in
                if displayPreferences.widgetVisible(widgetId, on: displayKey, global: settings.widgetVisibility[widgetId] ?? true) {
                    badge(for: widgetId)
                    if settings.separatorPositions.contains(widgetId) || widgetId == "Battery" {
                        Separator()
                    }
                }
            }

            // Date + Time (active)
            ActiveTimezoneBadge(
                city: activeTimezone.identifier != TimeZone.current.identifier ? cityLabel(for: activeTimezone) : "Local",
                time: formattedDateTime(for: activeTimezone)
            )
            .onTapGesture { showTimezonesPopover = true }
            .popover(isPresented: $showTimezonesPopover) {
                TimezonePopoverView(showPopover: $showTimezonesPopover)
            }
        }
        .onReceive(timer) { currentTime = $0 }
    }
}

// MARK: - Separator

struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(BarTheme.separator)
            .frame(width: 1, height: 14)
    }
}

// MARK: - TemperatureBadge

struct TemperatureBadge: View {
    @ObservedObject var service: TemperatureService
    @ObservedObject var settings = AppSettings.shared
    
    private var unitLabel: String {
        settings.temperatureUnit == "F" ? "°F" : "°C"
    }

    /// Formatted sensor value, or "--" when no real sensor is readable.
    private var valueText: String {
        guard let celsius = service.cpuTemperature else { return "--" }
        let shown = settings.temperatureUnit == "F" ? (celsius * 9 / 5) + 32 : celsius
        return "\(Int(shown.rounded()))\(unitLabel)"
    }

    /// OS thermal pressure wins over the raw sensor: macOS is already throttling.
    private var color: Color {
        switch service.thermalState {
        case .critical, .serious: return .red
        case .fair: return .yellow
        case .nominal: break
        @unknown default: break
        }
        guard let celsius = service.cpuTemperature else { return BarTheme.inactiveText }
        if celsius < 60 { return .green }
        if celsius < 80 { return .yellow }
        return .red
    }

    private var icon: String {
        switch service.thermalState {
        case .critical, .serious: return "flame.fill"
        default: return "thermometer"
        }
    }

    private var tooltip: String {
        let stateLabel: String
        switch service.thermalState {
        case .nominal: stateLabel = "Nominal"
        case .fair: stateLabel = "Fair"
        case .serious: stateLabel = "Serious (throttling)"
        case .critical: stateLabel = "Critical"
        @unknown default: stateLabel = "Unknown"
        }
        var parts = ["Thermal pressure: \(stateLabel)"]
        if let gpu = service.gpuTemperature {
            parts.append(String(format: "GPU: %.0f°C", gpu))
        }
        if !service.isAvailable {
            parts.append("No readable die sensor on this Mac")
        }
        return parts.joined(separator: " · ")
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            
            Text(valueText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .help(tooltip)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(0.12))
        )
        .foregroundStyle(color)
    }
}

// MARK: - InfoBadge

/// A single colored badge: `LABEL value`
struct InfoBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(BarTheme.inactiveText)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - TailscaleBadge

/// VPN state and time connected. Hidden entirely when Tailscale is not installed.
struct TailscaleBadge: View {
    @ObservedObject var service: TailscaleService
    let now: Date

    private var valueText: String {
        switch service.state {
        case .notInstalled: return ""
        case .unavailable: return "--"
        case .stopped: return "OFF"
        case .connecting: return "…"
        case .connected: return service.connectedDuration(now: now) ?? "ON"
        }
    }

    private var color: Color {
        service.isConnected ? BarTheme.badgeVpn : BarTheme.dimText
    }

    private var tooltip: String {
        switch service.state {
        case .notInstalled: return "Tailscale is not installed"
        case .unavailable: return "Tailscale status is unavailable"
        case .stopped: return "Tailscale is off or awaiting authorization (\(service.backendState))"
        case .connecting: return "Tailscale is connecting"
        case .connected:
            var parts: [String] = []
            if !service.tailnetName.isEmpty { parts.append(service.tailnetName) }
            if !service.tailscaleIP.isEmpty { parts.append(service.tailscaleIP) }
            if let since = service.connectedSince {
                let fmt = DateFormatter()
                fmt.dateStyle = .none
                fmt.timeStyle = .short
                parts.append("Observed online since \(fmt.string(from: since)). Not the actual tunnel connection time.")
            }
            return parts.joined(separator: " · ")
        }
    }

    var body: some View {
        if service.isInstalled {
            HStack(spacing: 4) {
                Image(systemName: service.isConnected ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(valueText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BarTheme.inactiveText)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.12))
            )
            .help(tooltip)
        }
    }
}

// MARK: - VolumeBadge

/// Output volume of the current default device. Shows `MUTE` when muted and
/// `--` when the device exposes no software volume control (typical for HDMI/DisplayPort monitors).
struct VolumeBadge: View {
    let volume: Int?
    let isMuted: Bool
    let deviceName: String

    private var valueText: String {
        if isMuted { return "MUTE" }
        guard let volume else { return "--" }
        return "\(volume)%"
    }

    private var tooltip: String {
        let device = deviceName.isEmpty ? "No output device" : deviceName
        if volume == nil && !deviceName.isEmpty {
            return "\(device) · no software volume control"
        }
        return device
    }

    var body: some View {
        InfoBadge(label: "VOL", value: valueText, color: BarTheme.badgeVolume)
            .help(tooltip)
    }
}

// MARK: - BatteryBadge

/// Battery with icon + percentage.
struct BatteryBadge: View {
    let level: Int
    let isCharging: Bool

    private var batteryColor: Color {
        if isCharging { return BarTheme.badgeBattery }
        if level <= 20 { return BarTheme.badgeRam }
        if level <= 50 { return BarTheme.badgeMic }
        return BarTheme.badgeBattery
    }

    private var batteryIcon: String {
        if isCharging { return "battery.100.bolt" }
        if level <= 10 { return "battery.0" }
        if level <= 25 { return "battery.25" }
        if level <= 50 { return "battery.50" }
        if level <= 75 { return "battery.75" }
        return "battery.100"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .font(.system(size: 11))
                .foregroundStyle(batteryColor)

            Text("\(level)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(BarTheme.inactiveText)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(batteryColor.opacity(0.12))
        )
    }
}

// MARK: - ActiveTimezoneBadge

/// Active timezone badge: `CITY time`
struct ActiveTimezoneBadge: View {
    let city: String
    let time: String

    var body: some View {
        HStack(spacing: 4) {
            Text(city)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(BarTheme.inactiveText.opacity(0.6))

            Text(time)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(BarTheme.badgeDate)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(BarTheme.badgeDate.opacity(0.12))
        )
    }
}

// MARK: - TimezonePopoverView

struct TimezoneItemView: View {
    let label: String
    let id: String
    @Binding var showPopover: Bool
    @ObservedObject var settings = AppSettings.shared
    
    var isActive: Bool {
        settings.previewTimezone == id || (settings.previewTimezone.isEmpty && id == AppSettings.localTimezoneIdentifier)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? .primary : .secondary)
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .contentShape(Rectangle()) // Make the whole area tappable
        .onTapGesture {
            settings.previewTimezone = id
            showPopover = false
        }
    }
}

// MARK: - TimezonePopoverView

struct TimezonePopoverView: View {
    @ObservedObject var settings = AppSettings.shared
    @Binding var showPopover: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select Timezone")
                .font(.system(size: 12, weight: .bold))
                .padding(12)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 4) {
                    TimezoneItemView(label: "Local", id: AppSettings.localTimezoneIdentifier, showPopover: $showPopover)
                    
                    ForEach(settings.extraTimezones, id: \.self) { tzId in
                        if TimeZone(identifier: tzId) != nil {
                            TimezoneItemView(
                                label: tzId.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? tzId,
                                id: tzId,
                                showPopover: $showPopover
                            )
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 200, height: 250)
    }
}
