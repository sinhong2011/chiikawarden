import SwiftUI
import VaultwardenAPI

/// Local password health checks; breach lookups only on request (k-anonymity, see `PwnedPasswords`).
struct WatchtowerReport {
    enum Issue: CaseIterable, Hashable {
        case breached, reused, weak, insecure, twoFactor

        /// Advice, not a problem: doesn't count against the score.
        var isAdvisory: Bool { self == .twoFactor }

        var title: LocalizedStringKey {
            switch self {
            case .breached: "Exposed in data breaches"
            case .reused: "Reused passwords"
            case .weak: "Weak passwords"
            case .insecure: "Unsecured websites"
            case .twoFactor: "Two-step login available"
            }
        }
        var symbol: String {
            switch self {
            case .breached: "exclamationmark.shield"
            case .reused: "arrow.triangle.2.circlepath"
            case .weak: "lock.open"
            case .insecure: "network.slash"
            case .twoFactor: "person.badge.shield.checkmark"
            }
        }
        var tint: Color {
            switch self {
            case .breached: .red
            case .reused, .weak: .orange
            case .insecure: .yellow
            case .twoFactor: .blue
            }
        }
        var advice: LocalizedStringKey {
            switch self {
            case .breached: "These passwords appear in known breaches. Change them on each site."
            case .reused: "One leak exposes every site that shares a password. Give each its own."
            case .weak: "Short or simple passwords are easy to guess. Generate a longer one."
            case .insecure: "These sites are saved with http://, so the password travels unencrypted."
            case .twoFactor: "These sites offer one-time codes. Turn two-step login on there, then save the code here."
            }
        }
    }

    let logins: [VaultItem]
    let issues: [Issue: [VaultItem]]

    /// `twoFactor`: sites that offer one-time codes (2fa.directory), by domain, with their setup guide.
    init(items: [VaultItem], breaches: [String: Int]?, twoFactor: [String: URL] = [:]) {
        logins = items.filter { !$0.isDeleted && $0.kind == .login && $0.password != nil }
        var issues: [Issue: [VaultItem]] = [:]
        for item in logins {
            guard let pw = item.password else { continue }
            if let n = breaches?[item.id], n > 0 { issues[.breached, default: []].append(item) }
            if item.reuseCount > 0 { issues[.reused, default: []].append(item) }
            if Self.isWeak(pw) { issues[.weak, default: []].append(item) }
            if let uri = item.uri, Self.isInsecure(uri) { issues[.insecure, default: []].append(item) }
            if item.totp == nil, !item.hasPasskey, let host = item.host, Self.guide(for: host, in: twoFactor) != nil {
                issues[.twoFactor, default: []].append(item)
            }
        }
        self.issues = issues
    }

    var problemCount: Int { Set(issues.filter { !$0.key.isAdvisory }.values.flatMap { $0.map(\.id) }).count }

    /// The setup guide for a host or the domain it falls under.
    static func guide(for host: String, in directory: [String: URL]) -> URL? {
        var parts = host.lowercased().split(separator: ".")
        while parts.count >= 2 {
            if let url = directory[parts.joined(separator: ".")] { return url }
            parts.removeFirst()
        }
        return nil
    }

    /// Share of logins with no issues, 0…1.
    var score: Double { logins.isEmpty ? 1 : 1 - Double(problemCount) / Double(logins.count) }

    static func isWeak(_ pw: String) -> Bool {
        let classes = [pw.contains(where: \.isLowercase), pw.contains(where: \.isUppercase),
                       pw.contains(where: \.isNumber), pw.contains { !$0.isLetter && !$0.isNumber }].filter { $0 }.count
        return pw.count < 10 || (pw.count < 14 && classes < 3)
    }

    /// http:// on a public host (local and private-network addresses are fine).
    static func isInsecure(_ uri: String) -> Bool {
        guard let url = URL(string: uri), url.scheme?.lowercased() == "http", let host = url.host()?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa")
            || host.hasSuffix(".internal") || !host.contains(".") { return false }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return false
            case (172, 16...31): return false
            default: return true
            }
        }
        return true
    }
}

struct WatchtowerView: View {
    @Environment(AppModel.self) private var model
    var onOpen: (VaultItem) -> Void
    @State private var directory: [String: URL] = [:]

    var body: some View {
        let report = WatchtowerReport(items: model.vaultItems, breaches: model.breachCounts, twoFactor: directory)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(report)
                ForEach(WatchtowerReport.Issue.allCases, id: \.self) { issue in
                    if let items = report.issues[issue], !items.isEmpty {
                        IssueCard(issue: issue, items: items, directory: directory, onOpen: onOpen)
                    }
                }
                if report.problemCount == 0 {
                    ContentUnavailableView("Looking good", systemImage: "checkmark.shield",
                                           description: Text(model.breachCounts == nil
                                               ? "No weak, reused or unsecured passwords. Check for breaches to be sure."
                                               : "No issues found."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .task { directory = await TwoFactorDirectory.load() }
    }

    private func header(_ report: WatchtowerReport) -> some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 9)
                Circle().trim(from: 0, to: report.score)
                    .stroke(report.score > 0.9 ? Color.green : report.score > 0.7 ? Color.orange : Color.red,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(verbatim: "\(Int((report.score * 100).rounded()))").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("score").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            .animation(.snappy, value: report.score)

            VStack(alignment: .leading, spacing: 6) {
                Text("Watchtower").font(.system(size: 24, weight: .bold))
                Text("\(report.problemCount) of \(report.logins.count) logins need attention.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await model.checkBreaches() }
                    } label: {
                        HStack(spacing: 6) {
                            if model.isCheckingBreaches { ProgressView().controlSize(.small) }
                            Text(model.breachCounts == nil ? "Check for breaches" : "Check again")
                        }
                    }
                    .buttonStyle(.appPrimarySmall)
                    .disabled(model.isCheckingBreaches || report.logins.isEmpty)
                    if let checked = model.breachesCheckedAt {
                        Text("Checked \(checked, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                Text("Sends only the first 5 characters of each password's SHA-1 hash to Have I Been Pwned. Passwords never leave this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
    }
}

private struct IssueCard: View {
    @Environment(AppModel.self) private var model
    let issue: WatchtowerReport.Issue
    let items: [VaultItem]
    var directory: [String: URL] = [:]
    var onOpen: (VaultItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: issue.symbol).foregroundStyle(issue.tint).font(.system(size: 15, weight: .semibold))
                Text(issue.title).font(.system(size: 15, weight: .semibold))
                Text(verbatim: "\(items.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(issue.tint.opacity(0.15), in: .capsule)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Text(issue.advice).font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
            ForEach(items) { item in
                Divider().padding(.leading, 16)
                HStack(spacing: 12) {
                    ItemIcon(item: item, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(verbatim: detail(item)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if issue == .twoFactor, let host = item.host, let guide = WatchtowerReport.guide(for: host, in: directory) {
                        Button("How to Turn On") { NSWorkspace.shared.open(guide) }
                            .buttonStyle(.appSecondarySmall)
                        Button("Add Code") { model.guarded(item) { model.editing = EditRequest(mode: .edit(item)) } }
                            .buttonStyle(.appSecondarySmall)
                    } else {
                        Button("Change Password") { model.guarded(item) { model.editing = EditRequest(mode: .edit(item)) } }
                            .buttonStyle(.appSecondarySmall)
                    }
                    Button { onOpen(item) } label: { Image(systemName: "arrow.right.circle").accessibilityLabel(Text("Open item")) }
                        .buttonStyle(.borderless)
                        .help(Text("Show item"))
                }
                .padding(.horizontal, 16).frame(minHeight: 48)
            }
        }
        .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
    }

    private func detail(_ item: VaultItem) -> String {
        switch issue {
        case .breached: String(localized: "Seen \(model.breachCounts?[item.id] ?? 0) times")
        case .reused: String(AttributedString(localized: "Shared with ^[\(item.reuseCount) other item](inflect: true)").characters)
        case .weak: [item.username, item.host].compactMap { $0 }.joined(separator: " · ")
        case .insecure: item.uri ?? ""
        case .twoFactor: [item.username, item.host].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// Sites that offer one-time codes, from 2fa.directory: the whole list is downloaded (nothing about the vault is
/// sent) and kept for a week.
enum TwoFactorDirectory {
    static let source = URL(string: "https://api.2fa.directory/v3/totp.json")!

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Chiikawarden")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "2fa-directory.json")
    }

    static func load() async -> [String: URL] {
        let cache = cacheURL
        let fresh = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date.now.timeIntervalSince($0) < 7 * 86_400 } ?? false
        if !fresh, let (data, response) = try? await URLSession.shared.data(from: source),
           (response as? HTTPURLResponse)?.statusCode == 200, !parse(data).isEmpty {
            try? data.write(to: cache, options: .atomic)
        }
        return (try? Data(contentsOf: cache)).map(parse) ?? [:]
    }

    /// `[[name, {domain, additional-domains, documentation, …}], …]` → domain: setup guide (or the site).
    static func parse(_ data: Data) -> [String: URL] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [:] }
        var out: [String: URL] = [:]
        for entry in list {
            guard entry.count > 1, let info = entry[1] as? [String: Any], let domain = info["domain"] as? String else { continue }
            let guide = (info["documentation"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://" + domain)!
            for d in [domain] + (info["additional-domains"] as? [String] ?? []) { out[d.lowercased()] = guide }
        }
        return out
    }
}
