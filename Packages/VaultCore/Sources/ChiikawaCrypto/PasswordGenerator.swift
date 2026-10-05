import Foundation
import Security

/// Random passwords from the system CSPRNG, with rejection sampling (no modulo bias) and at least
/// one character from every selected class.
public struct PasswordGenerator: Sendable, Equatable, Codable {
    public var length = 20
    public var uppercase = true
    public var lowercase = true
    public var digits = true
    public var symbols = true
    /// Drops look-alikes such as 0/O, 1/l/I.
    public var avoidAmbiguous = true

    public init() {}

    static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), lower = Array("abcdefghijklmnopqrstuvwxyz")
    static let numbers = Array("0123456789"), symbolSet = Array("!@#$%^&*-_=+?")
    static let ambiguous = Set("0O1lI")

    var classes: [[Character]] {
        [uppercase ? Self.upper : [], lowercase ? Self.lower : [], digits ? Self.numbers : [], symbols ? Self.symbolSet : []]
            .map { avoidAmbiguous ? $0.filter { !Self.ambiguous.contains($0) } : $0 }
            .filter { !$0.isEmpty }
    }

    public func generate() -> String {
        let classes = self.classes.isEmpty ? [Self.lower] : self.classes
        let all = classes.flatMap { $0 }
        let length = max(length, classes.count)
        // One from each class, the rest from the full set, then shuffle.
        var chars = classes.map { $0[Self.uniform(upTo: $0.count)] }
        while chars.count < length { chars.append(all[Self.uniform(upTo: all.count)]) }
        for i in stride(from: chars.count - 1, to: 0, by: -1) { chars.swapAt(i, Self.uniform(upTo: i + 1)) }
        return String(chars)
    }

    /// Entropy in bits, for the strength meter.
    public var entropyBits: Double { Double(max(length, 1)) * log2(Double(max(classes.flatMap { $0 }.count, 2))) }

    /// Uniform integer in 0..<n via rejection sampling.
    static func uniform(upTo n: Int) -> Int {
        precondition(n > 0)
        let limit = UInt32.max - UInt32.max % UInt32(n)
        while true {
            var r: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &r) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
            if r < limit { return Int(r % UInt32(n)) }
        }
    }
}
