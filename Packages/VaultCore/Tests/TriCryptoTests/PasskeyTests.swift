import CryptoKit
import Foundation
import Testing
@testable import TriCrypto

@Suite struct PasskeyTests {
    let clientDataHash = Data(SHA256.hash(data: Data(#"{"type":"webauthn.create","challenge":"abc","origin":"https://example.com"}"#.utf8)))

    @Test func cborEncoding() {
        #expect(CBOR.int(-7).encoded == Data([0x26]))
        #expect(CBOR.int(24).encoded == Data([0x18, 0x18]))
        #expect(CBOR.int(500).encoded == Data([0x19, 0x01, 0xF4]))
        #expect(CBOR.text("fmt").encoded == Data([0x63, 0x66, 0x6D, 0x74]))
        #expect(CBOR.map([]).encoded == Data([0xA0]))
        #expect(CBOR.bytes(Data(count: 32)).encoded.prefix(2) == Data([0x58, 0x20]))
    }

    @Test func credentialIDFormats() throws {
        let raw = try #require(Passkey.rawCredentialID("a2f5f2d4-5e2b-4c1e-8f3a-0123456789ab"))
        #expect(raw.count == 16 && raw.first == 0xA2 && raw.last == 0xAB)
        #expect(Passkey.rawCredentialID("b64.AQID") == Data([1, 2, 3]))
        #expect(Passkey.rawCredentialID("nope") == nil)
        #expect(Data(base64URL: Data([0xFB, 0xFF]).base64URLEncoded) == Data([0xFB, 0xFF]))
    }

    @Test func registerThenAssert() throws {
        let handle = Data("user-123".utf8)
        let reg = try Passkey.register(rpId: "example.com", rpName: "Example", userName: "usagi", userHandle: handle,
                                       clientDataHash: clientDataHash)
        #expect(reg.credential.rawId == reg.credentialID)
        #expect(reg.credential.rawUserHandle == handle)

        // attestationObject: {"fmt": "none", "attStmt": {}, "authData": h'…'}
        let att = reg.attestationObject
        #expect(att.prefix(1) == Data([0xA3]))
        let marker = CBOR.text("authData").encoded
        let range = try #require(att.range(of: marker))
        var authData = att[range.upperBound...]
        #expect(authData.first == 0x58) // bytes, 1-byte length (148)
        #expect(authData.dropFirst().first == 148)
        authData = authData.dropFirst(2)
        #expect(authData.prefix(32) == Data(SHA256.hash(data: Data("example.com".utf8))))
        #expect(authData[authData.startIndex + 32] == 0x5D) // UP UV BE BS AT
        let idLen = Int(authData[authData.startIndex + 53]) << 8 | Int(authData[authData.startIndex + 54])
        #expect(idLen == 16)
        let cose = authData.dropFirst(55 + idLen)
        let x = cose[(cose.startIndex + 10)..<(cose.startIndex + 42)]
        let y = cose[(cose.startIndex + 45)..<(cose.startIndex + 77)]
        let pub = try P256.Signing.PublicKey(rawRepresentation: x + y)

        let assertion = try Passkey.assert(reg.credential, clientDataHash: clientDataHash)
        #expect(assertion.credentialID == reg.credentialID && assertion.userHandle == handle && assertion.counter == 0)
        #expect(assertion.authenticatorData.count == 37 && assertion.authenticatorData[32] == 0x1D)
        let sig = try P256.Signing.ECDSASignature(derRepresentation: assertion.signature)
        #expect(pub.isValidSignature(sig, for: assertion.authenticatorData + clientDataHash))
    }

    @Test func counterAdvancesOnlyWhenCounting() throws {
        var cred = try Passkey.register(rpId: "example.com", userName: nil, userHandle: Data([1]), clientDataHash: clientDataHash).credential
        cred.counter = 7
        let a = try Passkey.assert(cred, clientDataHash: clientDataHash)
        #expect(a.counter == 8 && a.authenticatorData.suffix(4) == Data([0, 0, 0, 8]))
    }

    /// keyValue must be PKCS#8 so other Bitwarden clients can import it.
    @Test func keyIsPKCS8() throws {
        let cred = try Passkey.register(rpId: "example.com", userName: nil, userHandle: Data([1]), clientDataHash: clientDataHash).credential
        let der = try #require(Data(base64URL: cred.keyValue))
        let url = FileManager.default.temporaryDirectory.appending(path: "pk-\(UUID()).der")
        try der.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/openssl")
        p.arguments = ["pkcs8", "-nocrypt", "-inform", "DER", "-in", url.path, "-out", "/dev/null"]
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    @Test func rejectsOtherAlgorithms() {
        #expect(throws: Passkey.Failure.self) {
            try Passkey.register(rpId: "x", userName: nil, userHandle: Data([1]), clientDataHash: clientDataHash, algorithms: [-257])
        }
    }
}

@Suite struct EncArrayBufferTests {
    @Test func roundTripAndTamper() throws {
        let key = try SymmetricKeyPair(combined: Data((0..<64).map { UInt8($0) }))
        let file = Data((0..<10_000).map { UInt8($0 % 251) })
        var sealed = try EncArrayBuffer.encrypt(file, with: key)
        #expect(sealed[0] == 2 && sealed.count > file.count + 49)
        #expect(try EncArrayBuffer.decrypt(sealed, with: key) == file)
        // Works on a non-zero-based slice too.
        #expect(try EncArrayBuffer.decrypt((Data([9]) + sealed).dropFirst(), with: key) == file)
        sealed[sealed.count - 1] ^= 1
        #expect(throws: CryptoError.macMismatch) { try EncArrayBuffer.decrypt(sealed, with: key) }
        #expect(throws: CryptoError.self) { try EncArrayBuffer.decrypt(Data([2, 0, 0]), with: key) }
    }
}
