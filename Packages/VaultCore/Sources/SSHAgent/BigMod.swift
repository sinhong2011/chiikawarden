import Foundation

/// `a mod m` for big-endian unsigned magnitudes — just enough bignum to derive RSA CRT exponents
/// (OpenSSH key files don't store dP/dQ, Security.framework requires them).
enum BigMod {
    static func mod(_ a: Data, _ m: Data) -> Data {
        let mod = limbs(m)
        var r = [UInt32](repeating: 0, count: mod.count + 1)
        for byte in a {
            for bit in (0..<8).reversed() {
                shiftLeft(&r, bit: (byte >> bit) & 1)
                if compare(r, mod) >= 0 { subtract(&r, mod) }
            }
        }
        return bytes(r)
    }

    /// `a - 1` (a > 0).
    static func minusOne(_ a: Data) -> Data {
        var l = limbs(a)
        for i in l.indices { if l[i] == 0 { l[i] = .max } else { l[i] -= 1; break } }
        return bytes(l)
    }

    private static func limbs(_ d: Data) -> [UInt32] { // little-endian limbs
        let bytes = [UInt8](d)
        var out = [UInt32](repeating: 0, count: (bytes.count + 3) / 4)
        for (i, b) in bytes.reversed().enumerated() { out[i / 4] |= UInt32(b) << (8 * (i % 4)) }
        return out
    }

    private static func bytes(_ l: [UInt32]) -> Data {
        var out = Data()
        for limb in l.reversed() { out.append(contentsOf: [UInt8(limb >> 24), UInt8(limb >> 16 & 0xFF), UInt8(limb >> 8 & 0xFF), UInt8(limb & 0xFF)]) }
        return Data(out.drop { $0 == 0 })
    }

    private static func shiftLeft(_ r: inout [UInt32], bit: UInt8) {
        var carry = UInt32(bit)
        for i in r.indices {
            let next = r[i] >> 31
            r[i] = r[i] << 1 | carry
            carry = next
        }
    }

    private static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
        for i in stride(from: max(a.count, b.count) - 1, through: 0, by: -1) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    private static func subtract(_ a: inout [UInt32], _ b: [UInt32]) {
        var borrow: Int64 = 0
        for i in a.indices {
            var d = Int64(a[i]) - Int64(i < b.count ? b[i] : 0) - borrow
            borrow = d < 0 ? 1 : 0
            if d < 0 { d += 1 << 32 }
            a[i] = UInt32(d)
        }
    }
}
