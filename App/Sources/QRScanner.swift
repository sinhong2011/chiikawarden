import AppKit
import ScreenCaptureKit
import Vision

/// Reads a two-step login QR code off the screen, for the one-time code field: a copied image is read at once;
/// otherwise the system's window picker asks which window (or display) shows the code, and only that one is looked at,
/// once. The picker is the permission, so Triwarden never needs Screen Recording.
@MainActor
enum QRScanner {
    enum Failure: LocalizedError {
        case noCode, notTwoStep, migration, capture

        var errorDescription: String? {
            switch self {
            case .noCode: String(localized: "No QR code found there. Make it larger on screen and try again.")
            case .notTwoStep: String(localized: "That QR code isn't a two-step login code.")
            case .migration: String(localized: "That's a Google Authenticator export. Show the site's own QR code instead.")
            case .capture: String(localized: "Couldn't look at that window.")
            }
        }
    }

    /// An otpauth:// link from a copied image, or from the window the user picks. Nil when they cancel.
    static func scan() async throws -> String? {
        if let image = clipboardImage(), let link = try? twoStepLink(in: payloads(in: image)) { return link }
        guard let filter = await Picker.pick() else { return nil }
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int(filter.contentRect.width * scale))
        config.height = max(1, Int(filter.contentRect.height * scale))
        config.showsCursor = false
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) } catch { throw Failure.capture }
        return try twoStepLink(in: payloads(in: image))
    }

    private static func twoStepLink(in payloads: [String]) throws -> String {
        guard !payloads.isEmpty else { throw Failure.noCode }
        if let link = payloads.first(where: { $0.lowercased().hasPrefix("otpauth://") }) { return link }
        if payloads.contains(where: { $0.lowercased().hasPrefix("otpauth-migration://") }) { throw Failure.migration }
        throw Failure.notTwoStep
    }

    nonisolated static func payloads(in image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap(\.payloadStringValue) ?? []
    }

    private static func clipboardImage() -> CGImage? {
        guard let image = NSImage(pasteboard: .general) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// The issuer and account an otpauth:// link names ("otpauth://totp/GitHub:me@example.com?issuer=GitHub").
    static func details(of link: String) -> (issuer: String?, account: String?) {
        guard let components = URLComponents(string: link) else { return (nil, nil) }
        let label = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
        let parts = label.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let issuer = components.queryItems?.first { $0.name == "issuer" }?.value ?? (parts.count == 2 ? parts[0] : nil)
        let account = parts.last.flatMap { $0.isEmpty ? nil : $0 }
        return (issuer?.isEmpty == false ? issuer : nil, account)
    }

    /// The system's content-sharing picker, for one pick.
    @MainActor private final class Picker: NSObject, SCContentSharingPickerObserver {
        /// A filter is only read on the main actor once picked.
        struct Picked: @unchecked Sendable { let filter: SCContentFilter }
        private var continuation: CheckedContinuation<Picked?, Never>?
        private static var current: Picker?

        @MainActor static func pick() async -> SCContentFilter? {
            let picker = SCContentSharingPicker.shared
            let observer = Picker()
            current = observer
            var config = SCContentSharingPickerConfiguration()
            config.allowedPickerModes = [.singleWindow, .singleDisplay]
            config.excludedBundleIDs = Bundle.main.bundleIdentifier.map { [$0] } ?? []
            picker.defaultConfiguration = config
            picker.maximumStreamCount = 1
            picker.add(observer)
            picker.isActive = true
            let filter = await withCheckedContinuation { continuation in
                observer.continuation = continuation
                picker.present()
            }
            picker.remove(observer)
            picker.isActive = false
            current = nil
            return filter?.filter
        }

        private func finish(_ filter: SCContentFilter?) {
            continuation?.resume(returning: filter.map(Picked.init))
            continuation = nil
        }

        nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
            nonisolated(unsafe) let filter = filter
            Task { @MainActor in self.finish(filter) }
        }

        nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
            Task { @MainActor in self.finish(nil) }
        }

        nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
            Task { @MainActor in self.finish(nil) }
        }
    }
}
