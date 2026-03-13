import SwiftUI

// MARK: - SystemInfoView

/// Right side of the bar: RAM, CPU, MIC, VOL, Date, Battery — polybar style.
struct SystemInfoView: View {
    @EnvironmentObject var systemMonitor: SystemMonitorService

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            // RAM
            InfoBadge(
                label: "RAM",
                value: "\(systemMonitor.ramUsage)%",
                color: BarTheme.badgeRam
            )

            // CPU
            InfoBadge(
                label: "CPU",
                value: "\(systemMonitor.cpuUsage)%",
                color: BarTheme.badgeCpu
            )

            // GPU
            InfoBadge(
                label: "GPU",
                value: "\(systemMonitor.gpuUsage)%",
                color: BarTheme.badgeGpu
            )

            // MIC
            InfoBadge(
                label: "MIC",
                value: systemMonitor.isMicActive ? "ON" : "OFF",
                color: BarTheme.badgeMic
            )

            // VOL
            InfoBadge(
                label: "VOL",
                value: "\(systemMonitor.volume)%",
                color: BarTheme.badgeVolume
            )

            // Separator
            Rectangle()
                .fill(BarTheme.separator)
                .frame(width: 1, height: 14)

            // Date + Time
            Text(currentTime, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(BarTheme.badgeDate)

            // Separator
            Rectangle()
                .fill(BarTheme.separator)
                .frame(width: 1, height: 14)

            // Battery
            BatteryBadge(
                level: systemMonitor.batteryLevel,
                isCharging: systemMonitor.isCharging
            )
        }
        .onReceive(timer) { currentTime = $0 }
    }
}

// MARK: - InfoBadge

/// A single colored badge: `LABEL value`
struct InfoBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(BarTheme.inactiveText)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.12))
        )
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
        HStack(spacing: 3) {
            Image(systemName: batteryIcon)
                .font(.system(size: 11))
                .foregroundStyle(batteryColor)

            Text("\(level)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(BarTheme.inactiveText)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(batteryColor.opacity(0.12))
        )
    }
}
