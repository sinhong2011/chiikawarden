import SwiftUI
import UniformTypeIdentifiers
import VaultwardenAPI

/// Sidebar › Send: share text or a file through an end-to-end encrypted link that expires.
struct SendsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 10) {
                // Like the item list: a count (new Sends come from the header's + menu).
                HStack {
                    Text("\(model.sends.count) sends").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.leading, 6)
                .frame(height: 32)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.sends) { send in
                            SendRow(send: send, selected: send.id == model.selectedSendID && !model.composingSend)
                                .onTapGesture { model.composingSend = false; model.selectedSendID = send.id }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(send.id == model.selectedSendID ? [.isButton, .isSelected] : .isButton)
                                .accessibilityAction { model.composingSend = false; model.selectedSendID = send.id }
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                .contextMenu {
                                    Group {
                                        if let link = model.sendLink(send) {
                                            Button("Copy Link", systemImage: "link") { model.copyPlain(link.absoluteString) }
                                            Button("Open Link", systemImage: "safari") { NSWorkspace.shared.open(link) }
                                            Divider()
                                        }
                                        Button("Delete…", systemImage: "trash", role: .destructive) { model.confirmDeleteSend(send) }
                                    }
                                    .labelStyle(.titleAndIcon)
                                }
                        }
                    }
                    .padding(6)
                }
                .thinScroller()
                .background(Color.panel, in: .rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    if model.sends.isEmpty {
                        Text("Your Sends appear here.").font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(width: 300)

            Group {
                if model.composingSend {
                    SendComposer()
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else if let send = model.sends.first(where: { $0.id == model.selectedSendID }) {
                    SendDetail(send: send).id(send.id)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 26, weight: .medium)).foregroundStyle(Color.brand)
                            .frame(width: 64, height: 64)
                            .background(Color.brandFill.opacity(0.18), in: .circle)
                        Text("Share something securely").font(.system(size: 17, weight: .semibold))
                        Text("Send text or a file through an end-to-end encrypted link that expires on its own.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                        Button { compose() } label: { Label("New Send", systemImage: "plus") }
                            .buttonStyle(.appPrimary)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy(duration: 0.25), value: model.composingSend)
        }
    }

    private func compose() { withAnimation(.snappy(duration: 0.25)) { model.composingSend = true } }
}

private struct SendRow: View {
    let send: SendItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: send.kind == .file ? "doc" : "text.alignleft")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(send.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(status(send)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if send.hasPassword { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).frame(height: 48)
        .background(selected ? Color.panelStrong : .clear, in: .rect(cornerRadius: 11, style: .continuous))
        .contentShape(.rect)
    }
}

func status(_ send: SendItem) -> String {
    if send.disabled { return String(localized: "Disabled") }
    if send.isExpired { return String(localized: "Expired") }
    if send.isUsedUp { return String(localized: "Maximum views reached") }
    if let date = send.deletionDate {
        return String(localized: "Deletes \(date.formatted(.relative(presentation: .named)))")
    }
    return ""
}

private struct SendDetail: View {
    @Environment(AppModel.self) private var model
    let send: SendItem
    @State private var confirmDelete = false
    @State private var revealText = false

    var body: some View {
        let link = model.sendLink(send)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill").font(.system(size: 20)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.white.opacity(0.12), in: .rect(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(send.name).font(.system(size: 24, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            Text(status(send)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    if let link {
                        Text(verbatim: link.absoluteString)
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                        HStack(spacing: 10) {
                            Button { model.copyPlain(link.absoluteString) } label: { Label("Copy Link", systemImage: "link") }
                                .buttonStyle(HeroButtonStyle(prominent: true))
                            ShareLink(item: link) { Label("Share…", systemImage: "square.and.arrow.up") }
                                .buttonStyle(HeroButtonStyle(prominent: false))
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.hero, in: .rect(cornerRadius: 22, style: .continuous))

                VStack(spacing: 0) {
                    if send.kind == .text, let text = send.text {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Text").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    .textCase(.uppercase).tracking(0.6)
                                Spacer()
                                if send.hideText {
                                    Button(revealText ? "Hide" : "Reveal") { revealText.toggle() }.buttonStyle(.borderless).font(.caption)
                                }
                            }
                            Text(verbatim: send.hideText && !revealText ? String(repeating: "•", count: min(text.count, 24)) : text)
                                .font(.system(size: 13)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                    }
                    if send.kind == .file {
                        DetailRow(symbol: "doc", title: "File") {
                            Text(verbatim: [send.fileName, send.sizeName].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                        }
                    }
                    DetailRow(symbol: "eye", title: "Views") {
                        Text(send.maxAccessCount.map { "\(send.accessCount) / \($0)" } ?? "\(send.accessCount)").foregroundStyle(.secondary)
                    }
                    if let date = send.expirationDate {
                        DetailRow(symbol: "hourglass", title: "Expires") {
                            Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }
                    if let date = send.deletionDate {
                        DetailRow(symbol: "trash", title: "Deletes on") {
                            Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }
                    DetailRow(symbol: "lock", title: "Password") {
                        Text(send.hasPassword ? "Required" : "None").foregroundStyle(.secondary)
                    }
                    if let notes = send.notes, !notes.isEmpty {
                        DetailRow(symbol: "note.text", title: "Private notes") { Text(verbatim: notes).foregroundStyle(.secondary) }
                    }
                }
                .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))

                HStack {
                    Spacer()
                    Button("Delete Send", role: .destructive) { confirmDelete = true }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .confirmationDialog("Delete “\(send.name)”?", isPresented: $confirmDelete) {
            Button("Delete Send", role: .destructive) { Task { await model.deleteSend(send) } }
        } message: {
            Text("The link stops working immediately.")
        }
    }
}

private struct HeroButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : .white)
            .padding(.horizontal, 16).frame(height: 34)
            .background(prominent ? Color.white : Color.white.opacity(0.12), in: .capsule)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// New text or file Send, composed in place (no sheet): cards of soft fields, switches at the row ends.
struct SendComposer: View {
    @Environment(AppModel.self) private var model
    enum Kind: Hashable { case text, file }
    @State private var kind = Kind.text
    @State private var name = ""
    @State private var text = ""
    @State private var hideText = false
    @State private var file: URL?
    @State private var deleteAfterDays = 7
    @State private var expires = false
    @State private var expiration = Date.now.addingTimeInterval(86_400)
    @State private var limitViews = false
    @State private var maxViews = 1
    @State private var password = ""
    @State private var hideEmail = false
    @State private var notes = ""
    @State private var accountId: String?
    @State private var picking = false
    @State private var saving = false
    @State private var dropTargeted = false

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kind == .text ? !text.isEmpty : file != nil)
    }

    private func dismiss() { withAnimation(.snappy(duration: 0.25)) { model.composingSend = false } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormHeader(symbol: "paperplane.fill", title: "New Send",
                               subtitle: "Share text or a file through an encrypted link that expires.")

                    HStack(spacing: 12) {
                        AppSegmented(options: [(Kind.text, LocalizedStringKey("Text")), (.file, LocalizedStringKey("File"))],
                                     selection: $kind)
                            .frame(maxWidth: 260)
                        Spacer()
                        if model.sessions.count > 1 {
                            SoftMenu(options: model.sessions.map { (String?.some($0.id), $0.account.email) }, selection: $accountId,
                                     accessibilityLabel: "Account")
                                .frame(maxWidth: 240)
                        }
                    }

                    FormCard {
                        FormField(label: "Name") {
                            TextField("Name", text: $name, prompt: Text("e.g. Wi-Fi password")).textFieldStyle(SoftFieldStyle())
                        }
                        if kind == .text {
                            FormField(label: "Text") {
                                SoftEditor(text: $text, minHeight: 120)
                            }
                            Toggle("Hide the text until the recipient reveals it", isOn: $hideText).toggleStyle(.trailingSwitch)
                        } else {
                            FormField(label: "File") { fileZone }
                        }
                    }

                    FormCard(title: "Availability") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Delete after").font(.system(size: 13))
                            // The same sliding segments as Text / File, not a pop-up menu.
                            AppSegmented(options: [1, 2, 3, 7, 14, 30].map { days in
                                (days, days == 1 ? LocalizedStringKey("1 day") : LocalizedStringKey("\(days) days"))
                            }, selection: $deleteAfterDays)
                            .accessibilityLabel(Text("Delete after"))
                        }
                        Toggle("Expire earlier", isOn: $expires).toggleStyle(.trailingSwitch)
                        if expires {
                            DatePicker("Expires", selection: $expiration,
                                       in: Date.now...Date.now.addingTimeInterval(Double(deleteAfterDays) * 86_400))
                                .font(.system(size: 13))
                        }
                        Toggle("Limit views", isOn: $limitViews).toggleStyle(.trailingSwitch)
                        if limitViews {
                            HStack {
                                Text("Views").font(.system(size: 13))
                                Spacer()
                                NumberStepper(value: $maxViews, range: 1...100)
                            }
                        }
                    }

                    FormCard(title: "Protection") {
                        FormField(label: "Password") {
                            PasswordField(title: "Password", text: $password, prompt: Text("Optional"))
                        }
                        Toggle("Hide my email address from recipients", isOn: $hideEmail).toggleStyle(.trailingSwitch)
                        FormField(label: "Private notes") {
                            TextField("Private notes", text: $notes, prompt: Text("Only you see these")).textFieldStyle(SoftFieldStyle())
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .thinScroller()

            FormFooter(action: "Create & Copy Link", busy: saving, disabled: !ready, cancel: dismiss,
                       submit: { Task { await create() } }) {
                Label("The link holds the key; the server never sees your content.", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { choose(url) }
        }
        .onAppear { accountId = model.defaultAccountId }
    }

    private func choose(_ url: URL) {
        file = url
        if name.isEmpty { name = url.lastPathComponent }
    }

    /// Choose or drop a file: a dashed zone that shows the file once chosen.
    private var fileZone: some View {
        Button { picking = true } label: {
            HStack(spacing: 12) {
                Image(systemName: file == nil ? "doc.badge.plus" : "doc.fill")
                    .font(.system(size: 22)).foregroundStyle(file == nil ? Color.secondary : Color.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: file?.lastPathComponent ?? String(localized: "Choose a file, or drop it here"))
                        .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(file == nil ? "Up to 500 MB" : "Click to choose another").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.primary.opacity(dropTargeted ? 0.08 : 0.03), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(dropTargeted ? 0.3 : 0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            choose(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func create() async {
        saving = true
        defer { saving = false }
        let content: SendDraft.Content
        if kind == .text {
            content = .text(text, hidden: hideText)
        } else {
            guard let file else { return }
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: file), data.count <= AppModel.attachmentLimit else {
                model.flash(String(localized: "Choose a file up to 500 MB."))
                return
            }
            content = .file(name: file.lastPathComponent, contents: data)
        }
        var draft = SendDraft(name: name, content: content, deletionDate: .now.addingTimeInterval(Double(deleteAfterDays) * 86_400))
        draft.expirationDate = expires ? expiration : nil
        draft.maxAccessCount = limitViews ? maxViews : nil
        draft.password = password.isEmpty ? nil : password
        draft.hideEmail = hideEmail
        draft.notes = notes
        if await model.createSend(draft, accountId: accountId) { dismiss() }
    }
}
