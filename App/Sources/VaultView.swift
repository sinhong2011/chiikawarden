import SwiftUI

struct VaultView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection: VaultItem.ID?
    @State private var section: String? = "all"

    private var filtered: [VaultItem] {
        let base = section == "favorites" ? model.items.filter(\.favorite) : model.items
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.username?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.host?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Vault") {
                    Label("All Items", systemImage: "square.grid.2x2")
                        .badge(model.items.count)
                        .tag("all")
                    Label("Favorites", systemImage: "star")
                        .badge(model.items.filter(\.favorite).count)
                        .tag("favorites")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } content: {
            List(filtered, selection: $selection) { item in
                ItemRow(item: item)
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: Text("Search"))
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            .toolbar {
                ToolbarItem {
                    Button("Lock Vault", systemImage: "lock") { model.lock() }
                }
            }
        } detail: {
            if let item = model.items.first(where: { $0.id == selection }) {
                ItemDetail(item: item)
                    .id(item.id)
                    .transition(.blurReplace)
            } else {
                ContentUnavailableView("No Item Selected", systemImage: "key.viewfinder",
                                       description: model.skippedOrgItems > 0
                                           ? Text("\(model.skippedOrgItems) organization items are hidden until org keys are supported.")
                                           : nil)
            }
        }
        .animation(.smooth(duration: 0.25), value: selection)
    }
}

struct ItemRow: View {
    let item: VaultItem

    var body: some View {
        HStack(spacing: 12) {
            Monogram(name: item.name, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).fontWeight(.semibold)
                if let username = item.username {
                    Text(username).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.hasTOTP {
                Text("2FA").font(.caption.bold()).foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ItemDetail: View {
    let item: VaultItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Monogram(name: item.name, size: 60)
                    VStack(alignment: .leading) {
                        Text(item.name).font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        if let host = item.host { Text(host).foregroundStyle(.secondary) }
                    }
                }
                if let username = item.username {
                    LabeledContent("Username", value: username)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Colored initial tile; color is derived from the name so it stays stable.
struct Monogram: View {
    let name: String
    let size: CGFloat

    private static let palette: [Color] = [.mochi, .orange, .indigo, .teal, .purple, .brown, .blue, .green]

    var body: some View {
        let hue = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.palette[abs(hue) % Self.palette.count].gradient,
                        in: .rect(cornerRadius: size * 0.3))
    }
}
