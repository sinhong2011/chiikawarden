# Security

Chiikawarden is a client for Vaultwarden and Bitwarden servers. It uses the same end-to-end encryption
as the official clients. The server only ever sees encrypted vault data, and your master password never
leaves your Mac.

## Reporting a vulnerability

Please **don't open a public issue**. Use **Security › Report a vulnerability** on
[the GitHub repository](https://github.com/sinhong2011/chiikawarden/security/advisories/new) instead, and
include steps to reproduce. You should get an answer within a week. Fixes ship as a new release, with credit
to you unless you'd rather stay anonymous.

Problems in Vaultwarden or Bitwarden themselves belong to those projects.

## Where secrets live

| Secret | Where | Protection |
|---|---|---|
| Master password | Memory only, during unlock | Never stored or sent. Only the derived *master password hash* goes to the server, at login. |
| Master key / stretched key | Memory only, during unlock | Derived with PBKDF2-SHA256 or Argon2id, using the KDF settings the server reports (bounds-checked so a hostile server can't make them trivially weak). |
| User key (vault key) | Memory while unlocked | On disk only as the server's *protected user key*: encrypted with the stretched master key (AES-256-CBC + HMAC-SHA256). |
| User key for Touch ID | `Accounts/<id>/biometric.json` | AES-GCM under a key from ECDH with a **Secure Enclave** P-256 key that requires `biometryCurrentSet`. Enrolling a new finger or removing Touch ID makes it unusable, and you then need the master password. |
| Organization keys, per-item keys | Memory while unlocked | Arrive RSA-OAEP or AES encrypted in the sync payload. |
| Vault cache | `Accounts/<id>/vault.json` | The sync payload exactly as the server sent it: every name, username, password, URI, note and field is still an EncString. Item ids, types, dates and folder/collection ids are visible. |
| Refresh token | Keychain (Keychain Sharing group `…chiikawarden.shared`) | `AfterFirstUnlockThisDeviceOnly`, never synced to iCloud. Shared with the AutoFill extension so it can save new passkeys. |
| Custom request headers (e.g. Cloudflare Access tokens) | Same Keychain group | Same as above. |
| Website-icon cache key | Same Keychain group | 256-bit random key. Icons are cached AES-GCM encrypted, under HMAC-SHA256 file names, so the cache doesn't reveal which sites you have. |
| Attachments | On the server; decrypted copies only while previewed | Each file has its own 512-bit key (encrypted with the item key) and is uploaded as an encrypted buffer. Quick Look gets a decrypted copy in a private (0700) folder in the sandbox's temp directory. It is deleted when the preview closes, on lock and at launch. On APFS, deleting a file doesn't scrub the disk blocks, so don't preview files you need forensically erased. |
| Passkeys | Inside the login item (`login.fido2Credentials`) | Encrypted with the item's key like any other field, and synced to your server. |

Files live in the App Group container
`~/Library/Group Containers/FX3VR69P5K.io.github.sinhong2011.chiikawarden/`. They are written atomically
with `completeUntilFirstUserAuthentication` file protection, and both the app and the extension are sandboxed.

## What the app does to limit exposure

- **Locking** drops every account's keys, decrypted items and server connection. Auto-lock after inactivity,
  and on sleep, display sleep or a user switch, are on by default.
- **Clipboard**: copied secrets are marked `org.nspasteboard.ConcealedType`, so clipboard managers skip them.
  They are cleared after 30 seconds by default, but only if the clipboard still holds the copied value.
- **AutoFill** never fills without you there. Every request requires Touch ID or the master password inside
  the extension, and `provideCredentialWithoutUserInteraction` always refuses. Only domains, usernames and
  passkey ids are shared with the system's QuickType list, never passwords.
- **Leaked-password check** (Watchtower) uses the Have I Been Pwned k-anonymity range API with padding.
  Only the first 5 hex characters of each SHA-1 are sent.
- **Self-hosted servers**: public `http://` servers are refused, while local-network `http://` is allowed for
  home labs. You can trust a private CA inside Chiikawarden only, without adding it to the system keychain.
- **Edits** patch the server's own JSON and send `lastKnownRevisionDate`, so fields this app doesn't
  understand survive and concurrent edits are rejected rather than overwritten.

## Threat model

**In scope.** These are protected against:
- A compromised or malicious server, or anyone who reads the server's database. They get ciphertext only.
  A server could still withhold or roll back data, which no Bitwarden-protocol client can prevent.
- Network attackers. TLS is required for anything not on the local network.
- Someone with your unlocked Mac while Chiikawarden is **locked**. They need the master password or your
  fingerprint.
- Other apps reading the vault files. The vault cache stays encrypted, and the sandbox keeps other apps out.

**Out of scope.** These are not protected against:
- Malware running as your user while the vault is **unlocked**. It can read memory, the screen or the
  clipboard.
- Someone who knows your master password.
- A weak master password. The KDF slows guessing but can't make a weak password strong.
- Swift can't guarantee secret bytes are wiped from freed memory. Locking releases them, but
  doesn't zero them.

## Cryptography

All primitives come from Apple CryptoKit / CommonCrypto, except Argon2id, which uses the reference
implementation ([P-H-C/phc-winner-argon2](https://github.com/P-H-C/phc-winner-argon2), pinned by commit).
The VaultCore test suite checks known-answer vectors for PBKDF2, Argon2id, HKDF stretching, EncString, TOTP
(RFC 6238) and passkey signatures. Integration tests run against real Vaultwarden servers (see `DevServer/`).
