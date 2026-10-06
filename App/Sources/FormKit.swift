import SwiftUI

// The app's form language, shared by every "new" and "edit" form (items, Sends, folders): a title with a line of
// help, white cards on the window's wash, labels above soft rounded fields, switches at the row's end, and one
// footer bar with the actions.

/// The form's heading: an icon tile, a title, and what the form is for.
struct FormHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = scheme == .dark ? Color.brandFill : Color.brand
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(scheme == .dark ? 0.18 : 0.12), in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.3)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A group of fields on a card.
struct FormCard<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).font(.system(size: 13, weight: .semibold)) }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
    }
}

/// A label above its field, with an optional note under it.
struct FormField<Content: View>: View {
    let label: LocalizedStringKey
    var note: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
    }
}

/// Multi-line text in the same soft, rounded look as `SoftFieldStyle`.
struct SoftEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 90
    var monospaced = false
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: monospaced ? 12 : 13, design: monospaced ? .monospaced : .default))
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(8)
            .frame(minHeight: minHeight)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? Color.brand : Color(nsColor: .separatorColor), lineWidth: focused ? 1.5 : 1))
            .shadow(color: focused ? Color.brand.opacity(0.18) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A choice from a list, drawn as a soft field with a chevron (not the system pop-up button).
struct SoftMenu<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var placeholder: LocalizedStringKey = "Choose"
    var accessibilityLabel: LocalizedStringKey

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.0
                } label: {
                    if option.0 == selection {
                        Label { Text(verbatim: option.1) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: option.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let current = options.first(where: { $0.0 == selection })?.1 {
                    Text(verbatim: current).foregroundStyle(.primary)
                } else {
                    Text(placeholder).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

/// The footer every form ends with: a note on the left, Cancel and the primary action on the right.
struct FormFooter<Note: View>: View {
    let action: LocalizedStringKey
    var busy = false
    var disabled = false
    let cancel: () -> Void
    let submit: () -> Void
    @ViewBuilder var note: Note

    var body: some View {
        HStack(spacing: 10) {
            note
            Spacer()
            Button("Cancel", action: cancel).buttonStyle(.appSecondary).keyboardShortcut(.cancelAction)
            Button(action: submit) {
                HStack(spacing: 6) {
                    if busy { ProgressView().controlSize(.small).tint(.white) }
                    Text(action)
                }
            }
            .buttonStyle(.appPrimary).keyboardShortcut(.defaultAction)
            .disabled(disabled || busy)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(alignment: .top) { Divider().opacity(0.5) }
    }
}

extension FormFooter where Note == EmptyView {
    init(action: LocalizedStringKey, busy: Bool = false, disabled: Bool = false, cancel: @escaping () -> Void,
         submit: @escaping () -> Void) {
        self.init(action: action, busy: busy, disabled: disabled, cancel: cancel, submit: submit) { EmptyView() }
    }
}

/// Choosing a folder when folders nest ("Work/Dev"): each level opens as a submenu (a cascader), a parent can be
/// chosen itself from the top of its submenu, and the field shows the path as a breadcrumb.
struct FolderCascader: View {
    let folders: [Grouping]
    @Binding var selection: String?

    private var path: String? {
        selection.flatMap { id in folders.first { $0.id == id }?.name }
    }

    var body: some View {
        Menu {
            Button { selection = nil } label: { check(selection == nil, "No Folder") }
            Divider()
            FolderLevel(nodes: FolderNode.tree(folders), selection: $selection)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selection == nil ? "tray" : "folder")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let path {
                    // Work › Dev: the parents quiet, the folder itself in full.
                    let parts = path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
                    (parts.dropLast().reduce(Text(verbatim: "")) { $0 + Text(verbatim: "\($1) › ").foregroundStyle(.secondary) }
                        + Text(verbatim: parts.last ?? path).foregroundStyle(.primary))
                        .lineLimit(1).truncationMode(.head)
                } else {
                    Text("No Folder").foregroundStyle(.primary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Folder"))
        .accessibilityValue(Text(verbatim: path ?? String(localized: "No Folder")))
    }
}

/// One level of the folder tree: leaves are choices, parents open a submenu.
private struct FolderLevel: View {
    let nodes: [FolderNode]
    @Binding var selection: String?

    var body: some View {
        ForEach(nodes) { node in
            if node.children.isEmpty {
                if let id = node.folderIds.first {
                    Button { selection = id } label: { check(node.folderIds.contains(selection ?? ""), node.name, symbol: "folder") }
                }
            } else {
                Menu {
                    // The parent itself, when it's a real folder (not just a prefix of its children's names).
                    if let id = node.folderIds.first {
                        Button { selection = id } label: { check(node.folderIds.contains(selection ?? ""), node.name, symbol: "folder") }
                        Divider()
                    }
                    FolderLevel(nodes: node.children, selection: $selection)
                } label: {
                    // A tick on the way to the chosen folder.
                    check(contains(node, selection), node.name, symbol: "folder")
                }
            }
        }
    }

    private func contains(_ node: FolderNode, _ id: String?) -> Bool {
        guard let id else { return false }
        return node.folderIds.contains(id) || node.children.contains { contains($0, id) }
    }
}

@ViewBuilder
private func check(_ on: Bool, _ title: LocalizedStringKey) -> some View {
    if on { Label(title, systemImage: "checkmark") } else { Text(title) }
}

@ViewBuilder
private func check(_ on: Bool, _ title: String, symbol: String) -> some View {
    Label { Text(verbatim: title) } icon: { Image(systemName: on ? "checkmark" : symbol) }
}
