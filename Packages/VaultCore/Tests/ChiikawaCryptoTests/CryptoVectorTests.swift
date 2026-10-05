import Foundation
import Testing
@testable import ChiikawaCrypto

/// Vectors generated independently with Python `hashlib` + `cryptography`.
@Suite struct CryptoVectorTests {
    let password = "correct horse battery staple"
    let email = "Usagi@Example.com "

    @Test func masterKeyAndHash() throws {
        let mk = try KDF.masterKey(password: password, email: email, config: .pbkdf2(iterations: 600_000))
        #expect(mk.hex == "3898203f6009bc75069cef1c27d71969bf108de2bec508cdb1ac07560101cfdc")
        #expect(try KDF.masterPasswordHash(masterKey: mk, password: password)
            == "tM3u7z89mYXDV19ySBwfDaI4vqo34N/6uwOJpzt8STU=")
    }

    @Test func stretchAndUnwrapUserKey() throws {
        let mk = Data(hex: "3898203f6009bc75069cef1c27d71969bf108de2bec508cdb1ac07560101cfdc")
        let stretched = try SymmetricKeyPair.stretched(masterKey: mk)
        #expect(stretched.encryptionKey.hex == "adea54e90448cc15d2e8b88c6f002349f9040405675044d16c5fb3b9b18e531e")
        #expect(stretched.macKey.hex == "271a61ce4037d9716749948001776d6948a9b95b9bb2f213e973c72e9bced896")

        let protectedKey = try EncString("2.ZGVmZ2hpamtsbW5vcHFycw==|jZ6MneNz7c3XjtcxcOu6sfZ44ehOnOQMv+MKsW4grVKhTI9Zki3l3V4g2C4nMERCrVdQnnV0IR8H1F7unUPmqKvC1mEPP8xlcOmnuqTurQ0=|2w5uJV1rPnBTSMQdZFLZIskgpte24FNQqJbBbG0+7io=")
        let userKey = try SymmetricKeyPair(combined: protectedKey.decrypt(with: stretched))
        #expect(userKey.encryptionKey == Data(0..<32))

        let name = try EncString("2.AAECAwQFBgcICQoLDA0ODw==|jKfvVupjU0mVa5/2hY3AJg==|GLOSjVfpNbfRdI1N1eJ92VmXUEj9BFR7r79rZ8d6dJA=")
        #expect(try name.decryptString(with: userKey) == "GitHub")
    }

    @Test func tamperedMacIsRejected() throws {
        let key = try SymmetricKeyPair(combined: Data(0..<64))
        let good = try EncString.encrypt(Data("hi".utf8), with: key)
        var mac = good.mac
        mac[0] ^= 1
        let bad = EncString(iv: good.iv, ciphertext: good.ciphertext, mac: mac)
        #expect(throws: CryptoError.macMismatch) { try bad.decrypt(with: key) }
    }

    @Test func roundTripAndSerialization() throws {
        let key = try SymmetricKeyPair(combined: Data((0..<64).reversed()))
        let enc = try EncString.encrypt(Data("ちいかわ".utf8), with: key)
        #expect(try EncString(enc.description).decryptString(with: key) == "ちいかわ")
    }

    @Test(arguments: [
        KDFConfig.pbkdf2(iterations: 5_000),
        .argon2id(iterations: 1, memoryMiB: 64, parallelism: 4),
        .argon2id(iterations: 3, memoryMiB: 4, parallelism: 4),
    ])
    func kdfDowngradeIsRejected(config: KDFConfig) {
        #expect(throws: CryptoError.self) { try config.validate() }
    }

    @Test func legacyEncTypesAreRejected() {
        #expect(throws: CryptoError.unsupportedEncType(0)) { try EncString("0.AAAA|BBBB") }
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init(hex: String) {
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            bytes.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        self.init(bytes)
    }
}
