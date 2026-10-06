import Foundation
import Testing
@testable import TriCrypto

@Suite struct GeneratorTests {
    @Test func wordListIsTheEFFList() {
        let list = PassphraseGenerator.wordList
        #expect(list.count == 7776 && Set(list).count == 7776)
        #expect(list.first == "abacus" && list.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "-" } })
    }

    @Test func passphraseShape() {
        var g = PassphraseGenerator()
        g.words = 6
        let words = g.generate().split(separator: "-")
        #expect(words.count >= 6) // EFF has a few hyphenated words
        g.separator = "."; g.capitalize = true; g.includeNumber = true; g.words = 4
        let p = g.generate()
        #expect(p.filter(\.isNumber).count == 1)
        #expect(p.split(separator: ".").allSatisfy { $0.first?.isUppercase == true })
        #expect(abs(PassphraseGenerator().entropyBits - 6 * log2(7776)) < 0.01)
        g.words = 99
        #expect(g.generate().split(separator: ".").count >= 20)
    }

    @Test func passwordMinimums() {
        var g = PasswordGenerator()
        g.length = 12; g.minNumbers = 4; g.minSpecial = 3
        for _ in 0..<200 {
            let p = g.generate()
            #expect(p.count == 12)
            #expect(p.filter(\.isNumber).count >= 4)
            #expect(p.filter { "!@#$%^&*-_=+?".contains($0) }.count >= 3)
            #expect(p.contains { $0.isUppercase } && p.contains { $0.isLowercase })
        }
        g.length = 2
        #expect(g.generate().count == 9) // minimums win over a too-short length (4 + 3 + A–Z + a–z)
        g.length = 500
        #expect(g.generate().count == 128)
    }

    @Test func oldSettingsStillDecode() throws {
        let old = Data(#"{"length":32,"uppercase":true,"lowercase":true,"digits":false,"symbols":true,"avoidAmbiguous":false}"#.utf8)
        let g = try JSONDecoder().decode(PasswordGenerator.self, from: old)
        #expect(g.length == 32 && !g.digits && g.minNumbers == 1 && g.minSpecial == 1)
    }

    @Test func usernames() {
        var u = UsernameGenerator()
        #expect(PassphraseGenerator.wordList.contains(u.generate() ?? ""))
        u.capitalize = true; u.includeNumber = true
        let w = u.generate() ?? ""
        #expect(w.first?.isUppercase == true && w.suffix(4).allSatisfy(\.isNumber))
        u.kind = .plusAddressed; u.email = "usagi+old@chiikawa.test"
        let plus = u.generate() ?? ""
        #expect(plus.hasPrefix("usagi+") && plus.hasSuffix("@chiikawa.test") && plus.count == "usagi+".count + 8 + "@chiikawa.test".count)
        u.email = "nope"
        #expect(u.generate() == nil)
        u.kind = .catchAll; u.domain = "@mail.example"
        #expect(u.generate()?.hasSuffix("@mail.example") == true)
        u.domain = "localhost"
        #expect(u.generate() == nil)
    }
}
