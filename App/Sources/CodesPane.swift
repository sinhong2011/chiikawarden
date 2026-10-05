import ChiikawaCrypto
import SwiftUI

/// Sidebar › One-Time Codes: every code at once, live, click to copy.
struct CodesPane: View {
    @Environment(AppModel.self) private var model
    @State private var copiedID: String?

    private var items: [VaultItem] {
        model.items.filter { !$0.isDeleted && $0.totp != nil }
            .sorted { ($0.favorite ? 0 : 1, $0.name) < ($1.favorite ? 0 : 1, $1.name) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("One-Time Codes").font(.system(size: 22, weight: .bold)).tracking(-0.3)
                if items.isEmpty {
                    ContentUnavailableView("No one-time codes", systemImage: "clock.badge.checkmark",
                                           description: Text("Add a code secret to a login to see it here."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                            ForEach(items) { item in
                                if let totp = item.totp {
                                    CodeCard(item: item, totp: totp, date: context.date, copied: copiedID == item.id) {
                                        model.copy(totp.code(at: .now), label: String(localized: "Code"))
                                        withAnimation(.snappy) { copiedID = item.id }
                                        Task {
                                            try? await Task.sleep(for: .seconds(1.4))
                                            if copiedID == item.id { withAnimation(.snappy) { copiedID = nil } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.never)
    }
}

private struct CodeCard: View {
    let item: VaultItem
    let totp: TOTP
    let date: Date
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false

    var body: some View {
        let period = Double(totp.period)
        let remaining = 1 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
        let left = totp.secondsRemaining(at: date)
        let code = totp.code(at: date)
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ItemIcon(item: item, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(verbatim: item.username ?? item.host ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    ZStack {
                        Circle().stroke(Color.brand.opacity(0.15), lineWidth: 3)
                        Circle().trim(from: 1 - remaining, to: 1)
                            .stroke(left <= 5 ? Color.orange : Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(verbatim: "\(left)").font(.system(size: 9, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .frame(width: 24, height: 24)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: code.prefix(code.count / 2) + " " + code.suffix(code.count - code.count / 2))
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: code)
                    Spacer()
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copied ? Color.brand : .secondary)
                        .opacity(copied || hovering ? 1 : 0)
                }
            }
            .padding(16)
            .background(Color.panelStrong.opacity(hovering ? 1 : 0.85), in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(copied ? Color.brand.opacity(0.6) : Color.panelEdge, lineWidth: copied ? 1.5 : 1))
            .shadow(color: Color(red: 0.12, green: 0.16, blue: 0.35).opacity(hovering ? 0.12 : 0.06), radius: hovering ? 14 : 8, y: 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: "\(item.name), \(code)"))
        .accessibilityHint(Text("Copies the code"))
    }
}
