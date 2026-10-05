import Darwin
import Foundation
import SSHAgent

// `cw` — talks to the running Chiikawarden app. Secrets need the vault unlocked and an approval
// (Touch ID or the Mac password) in the app.

let usage = """
usage: cw <command> [arguments]

  status                    whether the vault is unlocked
  list [query]              items (name, username/site); needs approval
  get <item> [--field F]    print a field: password (default), username, uri, notes, totp, or a custom field
  code <item>               print the current one-time code
  generate [--length N]     a new random password (works while locked)
  lock                      lock every account

<item> is an item id, an exact name, or a unique part of a name, username or site.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("cw: \(message)\n".utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first else { print(usage); exit(64) }
if first == "-h" || first == "--help" || first == "help" { print(usage); exit(0) }
guard let command = CLIRequest.Command(rawValue: first) else { fail("unknown command “\(first)”\n\n" + usage, code: 64) }
args.removeFirst()

@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...i + 1) }
    return args[i + 1]
}
var request = CLIRequest(command: command)
request.field = option("--field")
request.length = option("--length").flatMap(Int.init)
request.query = args.isEmpty ? nil : args.joined(separator: " ")
if [.get, .code].contains(command), request.query == nil { fail("\(command.rawValue) needs an item", code: 64) }

let group = "FX3VR69P5K.io.github.sinhong2011.chiikawarden"
let socket = ProcessInfo.processInfo.environment["CW_SOCKET"]
    ?? FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Group Containers/\(group)/\(CLISocket.name)").path
guard let fd = FramedSocketServer.connect(to: socket) else {
    fail("Chiikawarden isn't running, or “Command line” is off in Settings › Developer.")
}
defer { close(fd) }
guard let body = try? JSONEncoder().encode(request), FramedSocketServer.writeFrame(fd, body),
      let reply = FramedSocketServer.readFrame(fd, max: 8 * 1024 * 1024),
      let response = try? JSONDecoder().decode(CLIResponse.self, from: reply) else {
    fail("no answer from Chiikawarden")
}
guard response.ok else { fail(response.error ?? "failed") }
if let rows = response.rows {
    let width = min(rows.map(\.name.count).max() ?? 0, 40)
    for row in rows {
        print(row.name.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + row.detail + "  " + row.id)
    }
} else if let value = response.value {
    // No trailing newline when piped, so `cw get x | pbcopy` copies exactly the secret.
    if isatty(STDOUT_FILENO) != 0 { print(value) } else { FileHandle.standardOutput.write(Data(value.utf8)) }
}
