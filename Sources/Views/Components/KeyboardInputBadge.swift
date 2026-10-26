import SwiftUI

/// A native menu backed by macOS keyboard input sources, not app localization.
struct KeyboardInputBadge: View {
    @ObservedObject private var service = KeyboardInputService.shared
    @State private var showSelectionError = false

    var body: some View {
        Menu {
            ForEach(service.sources) { source in
                Toggle(source.name, isOn: Binding(
                    get: { service.selectedID == source.id },
                    set: { selected in
                        if selected, !service.select(id: source.id) { showSelectionError = true }
                    }
                ))
            }
            if service.sources.isEmpty {
                Text("No enabled keyboard input sources")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                Text(service.selectedSource?.shortLabel ?? "--")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(BarTheme.inactiveText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(BarTheme.inactiveText.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Keyboard input source: \(service.selectedSource?.name ?? "Unavailable"). Click to change.")
        .accessibilityLabel("Keyboard input source")
        .accessibilityValue(service.selectedSource?.name ?? "Unavailable")
        .alert("Could not change keyboard", isPresented: $showSelectionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(service.selectionError ?? "The input source is unavailable.")
        }
    }
}
