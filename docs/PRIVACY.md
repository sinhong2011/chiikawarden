# Privacy

The canonical privacy policy for users is on the website: `/privacy/` (and each locale prefix).

Summary (aligned with the app and site code):

- Vault data stays on **your** Vaultwarden / Bitwarden server; Triwarden decrypts on the Mac.
- On the Mac: encrypted local cache, Keychain (unlock, sessions, license if registered), and standard preferences —
  not for analytics.
- Purchased license keys and a random installation identifier are sent to Lemon Squeezy when activated on a Mac.
  Successful activations are saved locally without recurring checks. Re-registering or activating on another Mac
  makes another request. Offline-format keys are verified locally. See [Lemon Squeezy Privacy](https://www.lemonsqueezy.com/privacy).
- Sparkle may check GitHub for updates when enabled. See
  [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
- Watchtower queries Pwned Passwords with five characters of a SHA-1 password hash, never the password or
  complete hash. It can download 2FA Directory data and query saved sites for change-password pages.
- Enabled website icons send domain names to the account’s configured Vaultwarden or Bitwarden icon service.
- The marketing site is static; it may fetch public GitHub release/star metadata, loads Google Fonts
  ([Google Privacy Policy](https://policies.google.com/privacy)), and stores light/dark theme in `localStorage` only.
- For privacy questions, email [triwarden@protonmail.com](mailto:triwarden@protonmail.com).
