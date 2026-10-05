# Chiikawarden

A native macOS client for [Vaultwarden](https://github.com/dani-garcia/vaultwarden) and Bitwarden, written in Swift and SwiftUI.

> Early development (M0). Not ready for real vaults yet.

## Goals

- **Vaultwarden first** — also works with official Bitwarden accounts (bitwarden.com / bitwarden.eu), with first-class support for self-hosters: custom CAs / mTLS, extra headers (Cloudflare Access), server health at a glance.
- **Deep macOS integration** — system AutoFill for passwords, passkeys and one-time codes, Touch ID unlock, menu bar, global Quick Search, SSH agent, App Intents.
- **Beautiful** — Liquid Glass on macOS 26, with motion that feels physical.
- **Localized** — English, 繁體中文, 简体中文, 日本語 from day one (String Catalogs).

## Requirements

- macOS 26 or later
- Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

```bash
xcodegen generate
open Chiikawarden.xcodeproj
```

Core logic lives in the `Packages/VaultCore` Swift package and can be tested on its own:

```bash
cd Packages/VaultCore && swift test
```

## Layout

| Path | What |
|---|---|
| `Packages/VaultCore/Sources/ChiikawaCrypto` | KDF, key stretching, EncString (AES-256-CBC + HMAC-SHA256) |
| `Packages/VaultCore/Sources/VaultwardenAPI` | Prelogin, login (2FA, new-device verification), sync; cloud + self-hosted |
| `App/` | SwiftUI app |

## License

[MIT](LICENSE). Chiikawarden is not affiliated with Bitwarden, Inc. or the Vaultwarden project.

See [SECURITY.md](SECURITY.md) for where keys live and how to report a vulnerability, and
[ACCESSIBILITY.md](ACCESSIBILITY.md) for VoiceOver, keyboard and contrast notes.

## Command line

Turn on **Settings › Developer › Answer the cw command**, then link the bundled tool:

```bash
sudo ln -sf /Applications/Chiikawarden.app/Contents/MacOS/cw /usr/local/bin/cw
```

`cw get github | pbcopy`, `cw code github`, `cw list mail`, `cw generate --length 32`, `cw lock`.
Reading from the vault asks for Touch ID in the app.

Maintainers: see [docs/RELEASING.md](docs/RELEASING.md) for signing, notarization and the Homebrew cask.

## Development

```bash
make            # list commands
make run        # build and open the app
make test       # VaultCore unit tests
make selftest   # in-app self-test against the dev server (DevServer/, settings in local.mk)
make snapshots  # light/dark UI renders into build/snapshots
```

`make selftest-cloud` runs the self-test against Bitwarden cloud with an **empty test account** from `.env`
(`BITWARDEN_ACCOUNT`, `BITWARDEN_PASSWORD`; git ignores the file). It asks in the terminal for any emailed device code.
