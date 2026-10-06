import Foundation
import Security
import Testing
@testable import ChiikawaCrypto

@Suite struct PublicKeyTests {
    /// A fresh RSA key as PKCS#8, the way the profile stores it.
    func privateKey() throws -> RSAPrivateKey {
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        let key = try #require(SecKeyCreateRandomKey(attrs as CFDictionary, nil))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(key, nil) as Data?)
        let algorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        let pkcs8 = RSAPublicKey.der(tag: 0x30, [0x02, 0x01, 0x00] + algorithm + RSAPublicKey.der(tag: 0x04, Array(pkcs1)))
        return try RSAPrivateKey(pkcs8: Data(pkcs8))
    }

    @Test func wrapsForTheHolderOfThePrivateKey() throws {
        let mine = try privateKey()
        let spki = try mine.publicKeySPKI()
        #expect(spki.prefix(4) == Data([0x30, 0x82, 0x01, 0x22]), "2048-bit SubjectPublicKeyInfo")
        let theirs = try RSAPublicKey(spki: spki)
        let secret = Data((0..<64).map { UInt8($0) })
        let wrapped = try theirs.encrypt(secret)
        #expect(wrapped.hasPrefix("4."))
        #expect(try mine.decrypt(wrapped) == secret)
    }

    @Test func fingerprintIsFiveWordsAndStable() throws {
        let spki = Data((0..<294).map { UInt8($0 % 251) })
        let a = Fingerprint.phrase(publicKeySPKI: spki, material: "user-1")
        #expect(a.count == 5 && a.allSatisfy { !$0.isEmpty })
        #expect(a == Fingerprint.phrase(publicKeySPKI: spki, material: "user-1"))
        #expect(a != Fingerprint.phrase(publicKeySPKI: spki, material: "user-2"))
    }

    /// Base-7,776 digits of a known number: 7,776² + 3 × 7,776 + 5 → words 5, 3, 1, 0, 0.
    @Test func wordsAreBase7776DigitsLeastSignificantFirst() {
        let n = 7_776 * 7_776 + 3 * 7_776 + 5
        let bytes: [UInt8] = [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        let list = PassphraseGenerator.wordList
        #expect(Fingerprint.words(from: bytes) == [list[5], list[3], list[1], list[0], list[0]])
    }
}
