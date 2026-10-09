import AppKit
import CryptoKit
import ImageIO
import Observation
import SwiftUI
import VaultwardenAPI

/// Website icons, fetched from the account's own icon service (Vaultwarden `/icons/…`, or Bitwarden's for
/// official accounts) so domains only go to the provider you already use. The disk cache is encrypted and
/// its file names are keyed hashes, so it doesn't reveal which sites you use.
@MainActor @Observable
final class IconStore {
    static let shared = IconStore()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var inflight: Set<String> = []
    @ObservationIgnored private var missing: Set<String> = []
    /// Per icon server: hash of its generic "no icon" placeholder, so we show our own initial instead.
    @ObservationIgnored private var placeholders: [String: Task<Data?, Never>] = [:]
    @ObservationIgnored var makeSession: () -> URLSession = { .shared }
    /// Where icons come from for items without a signed-in account (the full demo vault, for screenshots).
    @ObservationIgnored var fallbackEnvironment: ServerEnvironment?

    private let cacheDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Icons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Random key in the Keychain; encrypts cached icons and keys their file names.
    private let key: SymmetricKey = {
        let service = "io.github.sinhong2011.triwarden.iconcache"
        if let data = Keychain.read(service: service), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        Keychain.write(key.withUnsafeBytes { Data($0) }, service: service)
        return key
    }()

    static var enabled: Bool { UserDefaults.standard.object(forKey: Pref.showIcons) as? Bool ?? true }

    func image(for host: String) -> NSImage? { images[host] }

    /// Loads from cache or fetches once per host; no-op when icons are off.
    func request(host: String, environment: ServerEnvironment?) {
        guard Self.enabled, images[host] == nil, !inflight.contains(host), !missing.contains(host),
              let source = Self.url(for: host, environment: environment) else { return }
        if let cached = readCache(host) { images[host] = cached; return }
        inflight.insert(host)
        let session = makeSession()
        let placeholder = placeholderHash(for: environment, session: session)
        Task {
            defer { inflight.remove(host) }
            guard let (data, response) = try? await session.data(from: source),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = Self.thumbnail(data), image.size.width >= 8,
                  await placeholder.value != Data(SHA256.hash(data: data)) else {
                missing.insert(host)
                return
            }
            images[host] = image
            writeCache(host, data)
        }
    }

    private func placeholderHash(for environment: ServerEnvironment?, session: URLSession) -> Task<Data?, Never> {
        guard let probe = Self.url(for: "triwarden-no-icon.invalid", environment: environment) else { return Task { nil } }
        let key = probe.host() ?? ""
        if let task = placeholders[key] { return task }
        let task = Task<Data?, Never> {
            guard let (data, _) = try? await session.data(from: probe) else { return nil }
            return Data(SHA256.hash(data: data))
        }
        placeholders[key] = task
        return task
    }

    /// Forget all icons (memory and disk), e.g. when icons are turned off.
    func clear() {
        images = [:]
        missing = []
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    static func url(for host: String, environment: ServerEnvironment?) -> URL? {
        let safe = host.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        guard !safe.isEmpty, let root = environment?.iconsURL else { return nil }
        return root.appending(path: "\(safe)/icon.png")
    }

    private func fileURL(_ host: String) -> URL {
        let name = HMAC<SHA256>.authenticationCode(for: Data(host.utf8), using: key).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appending(path: name)
    }

    private func readCache(_ host: String) -> NSImage? {
        guard let sealed = try? Data(contentsOf: fileURL(host)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key) else { return nil }
        return Self.thumbnail(data)
    }

    /// The icon decoded at no more than 128 px (it's never drawn larger than ~60 pt), so a site's 512 px favicon
    /// doesn't sit in memory at full size. Kept at its own size when smaller.
    static func thumbnail(_ data: Data, maxPixels: Int = 128) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return NSImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return NSImage(data: data) }
        // Points at 2×, so it stays sharp on Retina.
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
    }

    private func writeCache(_ host: String, _ data: Data) {
        guard let sealed = try? AES.GCM.seal(data, using: key).combined else { return }
        try? sealed.write(to: fileURL(host), options: .atomic)
    }
}

/// The site's icon when available, otherwise the coloured initial. Cards use the API brand mark (Visa, Mastercard, …).
struct ItemIcon: View {
    @Environment(AppModel.self) private var model
    let item: VaultItem
    let size: CGFloat

    var body: some View {
        let store = IconStore.shared
        Group {
            if item.kind == .card, let brand = item.properties["brand"]?.nilIfEmpty {
                CardBrandIcon(brand: brand, size: size)
                    .transition(.opacity)
            } else if let host = item.host, let image = store.image(for: host) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.16)
                    .frame(width: size, height: size)
                    .background(.white, in: .rect(cornerRadius: size * 0.29, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).strokeBorder(.black.opacity(0.08)))
                    .transition(.opacity)
            } else {
                Monogram(name: item.name, size: size)
            }
        }
        .animation(.easeOut(duration: 0.2), value: item.host.flatMap(store.image(for:)) != nil)
        .task(id: item.host) {
            guard item.kind != .card, let host = item.host else { return }
            store.request(host: host, environment: model.session(for: item.accountId)?.environment ?? store.fallbackEnvironment)
        }
    }
}

/// Credit-card network mark for the vault list and hero avatar. Drawn to match Bitwarden's brand set.
struct CardBrandIcon: View {
    let brand: String
    let size: CGFloat

    private var kind: Kind {
        switch brand.lowercased() {
        case "visa": .visa
        case "mastercard": .mastercard
        case "amex", "american express": .amex
        case "discover": .discover
        case "jcb": .jcb
        case "unionpay", "union pay": .unionPay
        case "diners club", "diners": .diners
        case "maestro": .maestro
        default: .other
        }
    }

    private enum Kind { case visa, mastercard, amex, discover, jcb, unionPay, diners, maestro, other }

    var body: some View {
        Group {
            switch kind {
            case .visa: visa
            case .mastercard: mastercard
            case .amex: amex
            case .discover: discover
            case .jcb: jcb
            case .unionPay: unionPay
            case .diners: diners
            case .maestro: maestro
            case .other: other
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.29, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).strokeBorder(.black.opacity(0.08)))
        .accessibilityHidden(true)
    }

    private var visa: some View {
        ZStack {
            Color(red: 0.10, green: 0.12, blue: 0.44)
            Text("VISA")
                .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                .italic()
                .tracking(size * 0.02)
                .foregroundStyle(.white)
        }
    }

    private var mastercard: some View {
        ZStack {
            Color(white: 0.96)
            HStack(spacing: -size * 0.22) {
                Circle().fill(Color(red: 0.92, green: 0.20, blue: 0.14))
                Circle().fill(Color(red: 0.98, green: 0.62, blue: 0.12))
            }
            .frame(width: size * 0.72, height: size * 0.42)
        }
    }

    private var amex: some View {
        ZStack {
            Color(red: 0.00, green: 0.44, blue: 0.81)
            Text("AMEX")
                .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                .tracking(size * 0.01)
                .foregroundStyle(.white)
        }
    }

    private var discover: some View {
        ZStack {
            Color(white: 0.96)
            VStack(spacing: size * 0.04) {
                Text("DISCOVER")
                    .font(.system(size: size * 0.14, weight: .bold, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.18))
                Capsule()
                    .fill(Color(red: 0.96, green: 0.45, blue: 0.10))
                    .frame(width: size * 0.38, height: size * 0.14)
            }
        }
    }

    private var jcb: some View {
        ZStack {
            Color(white: 0.96)
            HStack(spacing: size * 0.04) {
                brandChip("J", Color(red: 0.05, green: 0.35, blue: 0.70))
                brandChip("C", Color(red: 0.10, green: 0.55, blue: 0.30))
                brandChip("B", Color(red: 0.80, green: 0.15, blue: 0.20))
            }
        }
    }

    private var unionPay: some View {
        ZStack {
            Color(white: 0.96)
            HStack(spacing: -size * 0.08) {
                Capsule().fill(Color(red: 0.85, green: 0.15, blue: 0.15)).frame(width: size * 0.28, height: size * 0.42)
                Capsule().fill(Color(red: 0.10, green: 0.35, blue: 0.75)).frame(width: size * 0.28, height: size * 0.42)
                Capsule().fill(Color(red: 0.05, green: 0.55, blue: 0.35)).frame(width: size * 0.28, height: size * 0.42)
            }
        }
    }

    private var diners: some View {
        ZStack {
            Color(red: 0.00, green: 0.36, blue: 0.58)
            ZStack {
                Circle().strokeBorder(.white, lineWidth: size * 0.045).frame(width: size * 0.48, height: size * 0.48)
                Capsule().fill(.white).frame(width: size * 0.14, height: size * 0.36)
            }
        }
    }

    private var maestro: some View {
        ZStack {
            Color(white: 0.96)
            HStack(spacing: -size * 0.22) {
                Circle().fill(Color(red: 0.00, green: 0.40, blue: 0.75))
                Circle().fill(Color(red: 0.85, green: 0.10, blue: 0.30))
            }
            .frame(width: size * 0.72, height: size * 0.42)
        }
    }

    private var other: some View {
        ZStack {
            Color(white: 0.96)
            Image(systemName: "creditcard.fill")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
        }
    }

    private func brandChip(_ letter: String, _ color: Color) -> some View {
        Text(letter)
            .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size * 0.24, height: size * 0.42)
            .background(color, in: .rect(cornerRadius: size * 0.06))
    }
}
