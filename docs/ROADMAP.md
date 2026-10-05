# Chiikawarden roadmap

Owner: product. Updated 2026-10-05. Status: ✅ done · 🟡 in progress · ⬜ planned

## North star

A Mac-native password manager for Vaultwarden (and Bitwarden) people *prefer* over the official
app: instant to open, beautiful in light and dark, and woven into macOS (AutoFill, Touch ID,
Quick Search, menu bar, SSH agent).

## v0.1 — "usable every day" (exit criteria)

You can replace the official desktop app for **reading** your vault:

| # | Capability | Why it blocks daily use | Status |
|---|---|---|---|
| 1 | Log in: PBKDF2, TOTP 2FA, new-device email code | Can't get in otherwise | ✅ |
| 2 | Log in: **Argon2id** accounts | Many vaults (and Bitwarden's newer default) use it | ✅ |
| 3 | **Organization items** (RSA-wrapped org keys, per-item keys) | Shared/family items were invisible | ✅ |
| 4 | Every item type renders: login, card, identity, note, SSH key | Half the vault looked empty | ✅ |
| 5 | **Stay signed in**: unlock with master password offline; Touch ID unlock (Secure Enclave) | Logging in with the network every time is a non-starter | ✅ |
| 6 | Encrypted offline cache + background sync ✅, live updates (WebSocket) ⬜ | Must work on a plane; must reflect other devices | 🟡 |
| 7 | Copy, reveal, live TOTP, open website | Core jobs | ✅ |
| 8 | Search + filters + sidebar categories | Core jobs | ✅ |
| 9 | Settings: appearance, auto-lock, lock on sleep, clipboard, custom CA, extra headers | Self-hosters and security defaults | ✅ |
| 10 | Quick Search (⌥Space) + menu bar extra | The reason to go native | ⬜ |
| 11 | Localized: en, zh-Hant, zh-HK, zh-Hans, ja | Day-one requirement | ✅ (kept current per change) |

## v0.2 — "use it instead of the browser extension"

- **Multiple accounts** (e.g. personal Vaultwarden + work Bitwarden), one merged list with per-account colour and filter
- AutoFill credential provider extension (passwords, one-time codes) — system-wide in Safari/Chrome/apps
- Passkey provider
- Create / edit / delete items, password generator
- Favicons (privacy-respecting, cached), Watchtower screen (weak / reused / breached via HIBP k-anonymity)

## v0.3 — "power users"

- SSH agent with Touch ID per signature; git commit signing
- App Intents / Shortcuts, Services menu, `cw` CLI over XPC
- Send, attachments, collections management, emergency access (Vaultwarden)
- Safari Web Extension + Chromium native messaging (save prompts, inline fill)

## Quality bar (every change)

- Unit tests + dev-server integration tests pass (`DevServer/dev.sh test`)
- In-app lifecycle self-test passes (`Chiikawarden --selftest <server> <email> <password>`)
- Light **and** dark snapshots reviewed (`Chiikawarden --snapshot`)
- All new strings translated in all five locales
- No secrets in logs, UserDefaults or the repo; secrets in Keychain or memory only

## Decisions log

- 2026-10-05 Native Swift/SwiftUI, macOS 26+, self-distributed, MIT.
- 2026-10-05 Vaultwarden-first; official Bitwarden cloud also supported.
- 2026-10-05 UI follows the canvas "Vault window (static spec)"; **no Liquid Glass on custom components**, system sidebar only.
- 2026-10-05 Keyguard is reference-only (All Rights Reserved) — never port its code.
