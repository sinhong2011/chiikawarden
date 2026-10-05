import SwiftUI

/// Server choice as three selectable cards: what it is, and where it points.
struct ServerPicker: View {
    @Binding var selection: AppModel.ServerKind

    var body: some View {
        // The app's capsule switcher: one quiet control instead of three cards.
        AppSegmented(options: AppModel.ServerKind.allCases.map { ($0, $0.title) }, selection: $selection)
            .accessibilityLabel(Text("Server"))
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
