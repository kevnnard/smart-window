import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isEnabled: Bool
    let content: () -> Content

    init(title: String, icon: String, isEnabled: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self._isEnabled = isEnabled
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Button {
                    isEnabled.toggle()
                } label: {
                    Image(systemName: isEnabled ? "eye" : "eye.slash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isEnabled {
                content()
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}
