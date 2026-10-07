// Triwarden license keys (see App/Sources/License.swift). Run through make:
//
//   make license-keys                                  one-time: create the signing key (kept in your login keychain)
//   make license NAME="Usagi" EMAIL=u@example.com ORDER=12345   sign a key for a buyer
//
// The private key is read from TRIWARDEN_LICENSE_PRIVATE_KEY (base64, raw Ed25519) and never enters the repo.
import CryptoKit
import Foundation

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    let fields = Array(args.dropFirst())
    guard fields.count == 3 else { fail("usage: license.swift sign <name> <email> <order>") }
    guard let raw = ProcessInfo.processInfo.environment["TRIWARDEN_LICENSE_PRIVATE_KEY"].flatMap({ Data(base64Encoded: $0) }),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("TRIWARDEN_LICENSE_PRIVATE_KEY is missing or not a raw Ed25519 key (run make license-keys)")
    }
    let date = Date.now.formatted(.iso8601.year().month().day())
    // Keys in a fixed order, so the same buyer always gets the same payload shape.
    let payload = try JSONSerialization.data(withJSONObject: ["n": fields[0], "e": fields[1], "o": fields[2], "d": date],
                                             options: [.sortedKeys, .withoutEscapingSlashes])
    let signature = try key.signature(for: payload)
    print(base64URL(payload) + "." + base64URL(signature))
default:
    fail("usage: license.swift keygen | sign <name> <email> <order>")
}
