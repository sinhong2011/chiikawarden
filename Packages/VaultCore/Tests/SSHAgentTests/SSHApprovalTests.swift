import Testing
@testable import SSHAgent

@Test func walksToTheAppBundle() {
    let nodes = [
        ProcessNode(pid: 10, parent: 9, path: "/usr/bin/ssh"),
        ProcessNode(pid: 9, parent: 8, path: "/opt/homebrew/bin/git"),
        ProcessNode(pid: 8, parent: 1, path: "/Applications/Cursor.app/Contents/MacOS/Cursor"),
    ]
    let byPID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.pid, $0) })
    let who = SSHRequesterResolver.resolve(pid: 10, peerPath: "/usr/bin/ssh", peerName: "ssh") { byPID[$0] }
    #expect(who.displayName == "Cursor")
    #expect(who.via == "ssh")
    #expect(who.peerPath == "/usr/bin/ssh")
    #expect(who.appPath == "/Applications/Cursor.app")
    #expect(who.appPID == 8)
    #expect(who.trustKey == "path:/Applications/Cursor.app")
}

@Test func bareToolTrustsItsOwnPath() {
    let who = SSHRequesterResolver.resolve(pid: 4, peerPath: "/usr/bin/ssh", peerName: "ssh") { pid in
        pid == 4 ? ProcessNode(pid: 4, parent: 1, path: "/usr/bin/ssh") : nil
    }
    #expect(who.displayName == "ssh")
    #expect(who.appPath == nil)
    #expect(who.trustKey == "path:/usr/bin/ssh")
}

@Test func stopsAfterEightSteps() {
    let who = SSHRequesterResolver.resolve(pid: 20, peerPath: "/bin/zsh", peerName: "zsh") { pid in
        ProcessNode(pid: pid, parent: pid + 1, path: "/bin/zsh")
    }
    #expect(who.appPath == nil)
    #expect(who.trustKey == "path:/bin/zsh")
}
