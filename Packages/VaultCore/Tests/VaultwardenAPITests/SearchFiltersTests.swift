import Foundation
import Testing
@testable import VaultwardenAPI

@Suite struct SearchFiltersTests {
    @Test func readsTokens() {
        #expect(SearchToken("type:card") == .type(.card))
        #expect(SearchToken("TYPE:Logins") == .type(.login))
        #expect(SearchToken("type:ssh-key") == .type(.sshKey))
        #expect(SearchToken("is:fav") == .favorites)
        #expect(SearchToken("has:otp") == .hasCode)
        #expect(SearchToken("has:2fa") == .hasCode)
        #expect(SearchToken("has:passkey") == .hasPasskey)
        #expect(SearchToken("is:weak") == .hasIssue)
        #expect(SearchToken("is:reused") == .hasIssue)
        #expect(SearchToken("folder:Work") == .folder("Work"))
        #expect(SearchToken("#Work") == .folder("Work"))
        #expect(SearchToken("folder:\"Home Office\"") == .folder("Home Office"))
        #expect(SearchToken("vault:personal") == .vault("personal"))
        #expect(SearchToken("in:Northwind") == .vault("Northwind"))
    }

    @Test func plainWordsStayText() {
        #expect(SearchToken("github") == nil)
        #expect(SearchToken("type:spaceship") == nil)
        #expect(SearchToken("folder:") == nil)
        #expect(SearchToken("#") == nil)
        #expect(SearchToken("https://example.com") == nil)
        #expect(SearchToken("is:nothing") == nil)
    }

    @Test func canonicalTextReadsBack() {
        let all: [SearchToken] = [.type(.login), .type(.card), .type(.identity), .type(.note), .type(.sshKey), .folder("Home Office"),
                                  .vault("Northwind"), .favorites, .hasCode, .hasPasskey, .hasIssue]
        for token in all {
            let words = SearchToken.words(token.text)
            #expect(words.count == 1)
            #expect(SearchToken(words[0]) == token)
        }
    }

    @Test func splitsQuotedWords() {
        #expect(SearchToken.words("folder:\"Home Office\" bank") == ["folder:\"Home Office\"", "bank"])
        #expect(SearchToken.words("  a   b ") == ["a", "b"])
    }

    @Test func extractsOnlyFinishedTokens() {
        // Still typing the last word: it stays text.
        var r = SearchToken.extract(from: "type:car")
        #expect(r.tokens.isEmpty && r.text == "type:car")
        r = SearchToken.extract(from: "type:card ")
        #expect(r.tokens == [.type(.card)] && r.text.isEmpty)
        r = SearchToken.extract(from: "git type:card has:otp hub")
        #expect(r.tokens == [.type(.card), .hasCode] && r.text == "git hub")
        r = SearchToken.extract(from: "bank ")
        #expect(r.tokens.isEmpty && r.text == "bank ")
        // An unfinished quote isn't a token yet.
        r = SearchToken.extract(from: "folder:\"Home ")
        #expect(r.tokens.isEmpty)
        // On Return, the last word counts too.
        r = SearchToken.extract(from: "is:fav", finishedOnly: false)
        #expect(r.tokens == [.favorites] && r.text.isEmpty)
        // A token the caller turns down stays where it was typed.
        r = SearchToken.extract(from: "a #Nowhere type:note b ", accepts: { $0 != .folder("Nowhere") })
        #expect(r.tokens == [.type(.note)] && r.text == "a #Nowhere b ")
    }

    @Test func applyAndRemove() {
        var f = SearchFilters()
        #expect(f.isEmpty && f.count == 0)
        f.apply(.type(.note)); f.apply(.favorites); f.apply(.folder("Work")); f.apply(.vault("x"))
        #expect(f.count == 3)
        #expect(f.tokens == [.type(.note), .folder("Work"), .favorites])
        f.apply(.type(.card)) // one type at a time: the newer one wins
        #expect(f.type == .card)
        f.remove(.favorites); f.remove(.type(.card)); f.remove(.folder("Work"))
        #expect(f.isEmpty)
    }

    @Test func persists() throws {
        let defaults = try #require(UserDefaults(suiteName: "SearchFiltersTests-\(UUID().uuidString)"))
        #expect(SearchFilters.load(from: defaults).isEmpty)
        let f = SearchFilters(type: .sshKey, folder: "Work/Servers", hasCode: true, hasIssue: true)
        f.save(to: defaults)
        #expect(SearchFilters.load(from: defaults) == f)
        SearchFilters().save(to: defaults)
        #expect(defaults.data(forKey: SearchFilters.defaultsKey) == nil)
    }
}
