import AppKit

/// Where the user was when they called the palette or opened the menu bar panel: the app, and for a browser the
/// site of its front tab. The palette and the panel put that site's (or app's) logins first.
struct ForegroundContext: Equatable {
    let app: String
    let bundleID: String
    let pid: pid_t
    /// The front tab's host, once the browser has answered (nil for other apps, or if the user declined).
    var host: String?

    var isBrowser: Bool { Self.browsers[bundleID] != nil }

    /// Browsers whose front tab we can ask for, and how (see `pageURL`). Each needs its bundle ID in the
    /// `temporary-exception.apple-events` entitlement; macOS asks the user once per browser.
    static let browsers: [String: Kind] = [
        "com.apple.Safari": .safari, "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium, "com.google.Chrome.beta": .chromium, "com.google.Chrome.canary": .chromium,
        "com.brave.Browser": .chromium, "com.microsoft.edgemac": .chromium, "company.thebrowser.Browser": .chromium,
        "company.thebrowser.dia": .chromium, "com.vivaldi.Vivaldi": .chromium, "org.chromium.Chromium": .chromium,
        "com.operasoftware.Opera": .chromium,
    ]
    enum Kind { case safari, chromium }

    init(app: String, bundleID: String, pid: pid_t, host: String?) {
        self.app = app; self.bundleID = bundleID; self.pid = pid; self.host = host
    }

    init(_ app: NSRunningApplication) {
        self.app = app.localizedName ?? ""
        bundleID = app.bundleIdentifier ?? ""
        pid = app.processIdentifier
    }

    /// The front tab's address, asked over Apple Events off the main thread (the first time, macOS shows its
    /// permission prompt and this waits for the answer). nil when there's no window or the user said no.
    static func pageURL(bundleID: String) async -> URL? {
        guard let kind = browsers[bundleID] else { return nil }
        let source = switch kind {
        case .safari: "tell application id \"\(bundleID)\" to return URL of front document"
        case .chromium: "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        }
        let text = await Task.detached(priority: .userInitiated) { () -> String? in
            var error: NSDictionary?
            return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        }.value
        guard let text, let url = URL(string: text), ["http", "https"].contains(url.scheme ?? "") else { return nil }
        return url
    }

    /// The vault's items for this context: logins for the site (equivalent domains count), or for another app,
    /// items named after it ("Discord" in Discord).
    @MainActor func items(in model: AppModel) -> [VaultItem] {
        let live = model.items.filter { !$0.isDeleted && !$0.isArchived && $0.kind == .login }
        if let host {
            let equivalents = model.equivalentDomains
            return Array(live.filter { item in
                guard let h = item.host, !h.isEmpty else { return false }
                return equivalents.matches(itemHost: h, site: host)
            }.prefix(6))
        }
        guard !isBrowser, app.count >= 3 else { return [] }
        let name = app.lowercased()
        return Array(live.filter { item in
            item.name.lowercased().contains(name) || (item.host?.lowercased().contains(name.replacingOccurrences(of: " ", with: "")) ?? false)
        }.prefix(6))
    }

    /// What the palette and the panel call it: "github.com" for a page, else the app's name.
    var label: String { host ?? app }
}

extension AppModel {
    /// Remembers the app the user was last in (anything but us), so the palette and the panel know where they
    /// were called from even after Triwarden comes forward.
    func trackForegroundApps() {
        lastOtherApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                          queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app != .current else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = app }
        }
    }

    /// Notes where the user is (the front app, or the last one before Triwarden), then asks a browser for its
    /// front tab. Call it before Triwarden takes focus.
    func captureForeground() {
        guard !foregroundPinned else { return }
        let front = NSWorkspace.shared.frontmostApplication
        guard let app = (front == .current ? lastOtherApp : front), !app.isTerminated else { foreground = nil; return }
        var context = ForegroundContext(app)
        guard context.isBrowser else { foreground = context; return }
        context.host = foreground?.bundleID == context.bundleID && foreground?.pid == context.pid ? foreground?.host : nil
        foreground = context
        Task {
            let host = await ForegroundContext.pageURL(bundleID: context.bundleID)?.host()?.lowercased()
            guard foreground?.pid == context.pid else { return }
            foreground?.host = host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        }
    }

    /// The global "fill" shortcut: types the one login for the page or app you're in. With several (or none),
    /// or while locked, the palette opens instead, already showing them.
    func fillForeground() {
        guard isUnlocked else { openPalette(); return }
        captureForeground()
        Task {
            if let context = foreground, context.isBrowser, context.host == nil {
                // Wait (briefly) for the browser to say which page it's on.
                for _ in 0..<20 where foreground?.host == nil && foreground?.pid == context.pid {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            guard let context = foreground else { openPalette(); return }
            let logins = context.items(in: self).filter { $0.password != nil }
            guard logins.count == 1, let item = logins.first else { openPalette(); return }
            guarded(item) {
                let steps: [AutoType.Step] = [item.username.map(AutoType.Step.text), item.username != nil ? .tab : nil,
                                              item.password.map(AutoType.Step.text)].compactMap { $0 }
                self.autoType(steps, into: context, fallback: item.password.map { (value: $0, label: String(localized: "Password")) })
            }
        }
    }

    /// Hands focus back to the app the palette was called from (after copying something for it).
    func returnToForeground() {
        guard let foreground, let app = NSRunningApplication(processIdentifier: foreground.pid) else { return }
        app.activate()
    }
}
