import CryptoKit
import Foundation

/// RFC 6238 one-time codes from a Bitwarden `totp` field (raw base32 or an `otpauth://` URI).
public struct TOTP: Sendable, Equatable {
    public enum Algorithm: String, Sendable { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }

    public let secret: Data
    public let digits: Int
    public let period: Int
    public let algorithm: Algorithm

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        var secretString = trimmed
        var digits = 6, period = 30, algorithm = Algorithm.sha1
        if let url = URLComponents(string: trimmed), url.scheme?.lowercased() == "otpauth" {
            let items = Dictionary((url.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") },
                                   uniquingKeysWith: { a, _ in a })
            guard let s = items["secret"] else { return nil }
            secretString = s
            digits = Int(items["digits"] ?? "") ?? 6
            period = Int(items["period"] ?? "") ?? 30
            algorithm = Algorithm(rawValue: (items["algorithm"] ?? "SHA1").uppercased()) ?? .sha1
        }
        guard let secret = Self.base32Decode(secretString), !secret.isEmpty,
              (1...10).contains(digits), period > 0 else { return nil }
        self.secret = secret
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
    }

    public func code(at date: Date = .now) -> String {
        var counter = UInt64(date.timeIntervalSince1970 / Double(period)).bigEndian
        let message = Data(bytes: &counter, count: 8)
        let key = SymmetricKey(data: secret)
        let mac: [UInt8] = switch algorithm {
        case .sha1: Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let o = Int(mac[mac.count - 1] & 0x0f)
        let bin = (UInt32(mac[o] & 0x7f) << 24) | (UInt32(mac[o + 1]) << 16) | (UInt32(mac[o + 2]) << 8) | UInt32(mac[o + 3])
        var mod: UInt32 = 1
        for _ in 0..<digits { mod = mod &* 10 }
        let n = String(bin % mod)
        return String(repeating: "0", count: digits - n.count) + n
    }

    public func secondsRemaining(at date: Date = .now) -> Int {
        period - Int(date.timeIntervalSince1970) % period
    }

    static func base32Decode(_ s: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0, value = 0
        var out = Data()
        for ch in s.uppercased() where ch != "=" && ch != " " && ch != "-" {
            guard let i = alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | i
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out
    }
}
