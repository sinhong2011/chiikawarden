import SwiftUI

/// How an account tells itself apart when several share the screen: one or two letters, unique among the accounts on
/// this Mac (sinhong2011 → "S2", sinhong516+test01 → "ST"), on a soft tint of its own. The letters carry the identity
/// and the tint only helps, so ten accounts read as clearly as two. Accounts are round; items keep their square tiles.
enum AccountIdentity {
    /// Soft hues for the tints (fills only; letters stay neutral).
    static let palette: [Color] = [.indigo, .orange, .green, .pink, .teal, .purple, .brown, .mint, .red, .yellow]

    static func tint(_ account: SavedAccount, among accounts: [SavedAccount]) -> Color {
        palette[(accounts.firstIndex { $0.id == account.id } ?? 0) % palette.count]
    }

    static func initials(_ account: SavedAccount, among accounts: [SavedAccount]) -> String {
        let others = accounts.filter { $0.id != account.id }
        let one = first(account)
        guard others.contains(where: { first($0) == one }) else { return one }
        let two = one + second(account)
        guard others.contains(where: { first($0) + second($0) == two }) else { return two }
        let position: Int = accounts.firstIndex { $0.id == account.id } ?? 0
        return one + String(position + 1)
    }

    /// The email's name part, split into runs of letters and of digits, before and after a "+tag".
    private static func parts(_ account: SavedAccount) -> (name: [String], tag: [String], domain: String) {
        let pieces = account.email.split(separator: "@", maxSplits: 1).map(String.init)
        let local = pieces.first ?? account.email
        let tagged = local.split(separator: "+", maxSplits: 1).map(String.init)
        func runs(_ s: String) -> [String] {
            var out: [String] = []
            var current = ""
            for c in s where c.isLetter || c.isNumber {
                if let last = current.last, last.isNumber != c.isNumber { out.append(current); current = "" }
                current.append(c)
            }
            if !current.isEmpty { out.append(current) }
            return out
        }
        return (runs(tagged.first ?? local), tagged.count > 1 ? runs(tagged[1]) : [], pieces.count > 1 ? pieces[1] : "")
    }

    private static func first(_ account: SavedAccount) -> String {
        let p = parts(account)
        var pick: Character? = p.name.first?.first
        if pick == nil { pick = p.tag.first?.first }
        if pick == nil { pick = account.email.first }
        return pick.map { String($0).uppercased() } ?? "?"
    }

    /// What tells two same-letter accounts apart: the +tag, else the name's last part (its digits), else the domain.
    private static func second(_ account: SavedAccount) -> String {
        let p = parts(account)
        var pick: Character? = p.tag.first?.first
        if pick == nil, p.name.count > 1 { pick = p.name.last?.first }
        if pick == nil { pick = p.domain.first }
        return pick.map { String($0).uppercased() } ?? ""
    }
}

/// An account's round avatar: its letters on its tint; optionally a lock while it's locked.
struct AccountAvatar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let account: SavedAccount
    var size: CGFloat = 28
    var showsLock = false

    var body: some View {
        let tint = AccountIdentity.tint(account, among: model.accounts)
        let letters = AccountIdentity.initials(account, among: model.accounts)
        Text(verbatim: letters)
            .font(.system(size: size * (letters.count > 1 ? 0.36 : 0.44), weight: .semibold, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.85))
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(scheme == .dark ? 0.36 : 0.24)))
            .overlay(Circle().strokeBorder(tint.opacity(scheme == .dark ? 0.55 : 0.4), lineWidth: max(1, size / 32)))
            .overlay(alignment: .bottomTrailing) {
                if showsLock, !model.isUnlocked(account.id) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: size * 0.42, height: size * 0.42)
                        .background(Color.windowBase, in: .circle)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .offset(x: size * 0.08, y: size * 0.08)
                }
            }
            .accessibilityHidden(true) // the email is read beside it
    }
}

/// Several accounts at once: up to three avatars overlapping, then "+N" for the rest.
struct AccountAvatarStack: View {
    @Environment(\.colorScheme) private var scheme
    let accounts: [SavedAccount]
    var size: CGFloat = 24

    /// How many circles the stack draws (avatars + optional "+N"), capped the same way as `body`.
    private static func circleCount(forAccountCount count: Int) -> Int {
        guard count > 0 else { return 0 }
        // >3 accounts → 2 avatars + "+N"; otherwise one circle per account (max 3).
        return count > 3 ? 3 : count
    }

    /// Layout width for a stack of `count` accounts at `size` (overlap −0.26×size, plus the ring gap).
    static func width(forAccountCount count: Int, size: CGFloat) -> CGFloat {
        let n = CGFloat(circleCount(forAccountCount: count))
        guard n > 0 else { return 0 }
        let overlap = size * 0.26
        let rings: CGFloat = 3 // `.padding(-1.5)` halo on each end
        return size * n - overlap * (n - 1) + rings
    }

    var body: some View {
        let shown = Array(accounts.prefix(accounts.count > 3 ? 2 : 3))
        let extra = accounts.count - shown.count
        HStack(spacing: -size * 0.26) {
            // The first on top, so every one keeps its letters readable.
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, account in
                AccountAvatar(account: account, size: size)
                    .background(Circle().fill(Color.windowBase).padding(-1.5)) // a gap where they overlap
                    .zIndex(Double(shown.count - i))
            }
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.primary.opacity(scheme == .dark ? 0.16 : 0.08)))
                    .background(Circle().fill(Color.windowBase).padding(-1.5))
            }
        }
        .accessibilityHidden(true)
    }
}

/// On an item, when several accounts are open: whose it is, as the account's letters in a small tinted tag.
struct AccountTag: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let accountId: String

    var body: some View {
        if model.sessions.count > 1, let account = model.accounts.first(where: { $0.id == accountId }) {
            let tint = AccountIdentity.tint(account, among: model.accounts)
            Text(verbatim: AccountIdentity.initials(account, among: model.accounts))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.75))
                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 16)
                .background(tint.opacity(scheme == .dark ? 0.32 : 0.2), in: .capsule)
                .help(Text(verbatim: account.email))
                .accessibilityLabel(Text(verbatim: account.email))
        }
    }
}
