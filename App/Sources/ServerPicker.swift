import SwiftUI

/// Server choice as three selectable cards: what it is, and where it points.
struct ServerPicker: View {
    @Binding var selection: AppModel.ServerKind

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppModel.ServerKind.allCases) { kind in
                ServerCard(kind: kind, isSelected: kind == selection) {
                    withAnimation(.snappy(duration: 0.22)) { selection = kind }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Server"))
    }
}

private struct ServerCard: View {
    let kind: AppModel.ServerKind
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? Color.brand : .secondary)
                        .frame(width: 20, height: 18)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color.brand : Color.secondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title).font(.system(size: 13, weight: .semibold))
                    Text(kind.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.brand.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.brand : Color(nsColor: .separatorColor).opacity(isHovered ? 1 : 0.7),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension AppModel.ServerKind {
    var symbol: String {
        switch self {
        case .bitwardenUS: "cloud"
        case .bitwardenEU: "globe.europe.africa"
        case .selfHosted: "server.rack"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .bitwardenUS: "Bitwarden"
        case .bitwardenEU: "Bitwarden EU"
        case .selfHosted: "Self-hosted"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .bitwardenUS: "bitwarden.com"
        case .bitwardenEU: "bitwarden.eu"
        case .selfHosted: "Vaultwarden"
        }
    }
}
