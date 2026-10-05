import Foundation
import Observation

/// Opt-in check against the project's latest GitHub release. It only compares version numbers and links
/// to the release page; nothing is downloaded or installed automatically, and nothing is sent but the request.
@MainActor @Observable
final class UpdateChecker {
    struct Release: Equatable { let version: String; let page: URL }

    private(set) var available: Release?
    private(set) var lastChecked: Date?
    private(set) var checking = false
    private(set) var error: String?
    private var timer: Timer?

    static let endpoint = URL(string: "https://api.github.com/repos/sinhong2011/chiikawarden/releases/latest")!
    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Checks now and then daily, while the setting is on.
    func schedule() {
        timer?.invalidate()
        timer = nil
        guard UserDefaults.standard.bool(forKey: Pref.checkUpdates) else { available = nil; return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func check(session: URLSession = .shared) async {
        checking = true
        defer { checking = false; lastChecked = .now }
        struct Latest: Decodable { let tag_name: String; let html_url: URL; let draft: Bool?; let prerelease: Bool? }
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 { available = nil; error = nil; return } // no releases yet
            let latest = try JSONDecoder().decode(Latest.self, from: data)
            let version = latest.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            available = Self.isNewer(version, than: current) && latest.draft != true && latest.prerelease != true
                ? Release(version: version, page: latest.html_url) : nil
            error = nil
        } catch {
            self.error = String(localized: "Couldn't check for updates.")
        }
    }

    /// Numeric, component-wise: 0.10.0 > 0.9.3.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
