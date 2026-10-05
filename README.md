# Chiikawarden

A native macOS client for [Vaultwarden](https://github.com/dani-garcia/vaultwarden), written in Swift and SwiftUI.

> Early development (M0). Not ready for real vaults yet.

## Goals

- **Vaultwarden only** — first-class support for self-hosters: custom CAs / mTLS, extra headers (Cloudflare Access), server health at a glance.
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
| `Packages/VaultCore/Sources/VaultwardenAPI` | Prelogin, login, sync |
| `App/` | SwiftUI app |

## License

[MIT](LICENSE). Chiikawarden is not affiliated with Bitwarden, Inc. or the Vaultwarden project.
