# Releasing

Releases are automatic once the one-time setup is done:

1. Commits on `main` use [Conventional Commits](https://www.conventionalcommits.org): `feat: …`, `fix: …`,
   `perf: …`, `security: …` show up in the changelog; `docs:`, `chore:`, `test:` don't. `feat!:` or a
   `BREAKING CHANGE:` footer marks a breaking change (before 1.0 that bumps the minor version).
2. [release-please](https://github.com/googleapis/release-please) keeps a **release PR** open with the next version
   (in `project.yml`) and `CHANGELOG.md`.
3. Merging the release PR tags `vX.Y.Z` and creates the GitHub release. The `build` job in
   `.github/workflows/release.yml` then runs `scripts/release.sh X.Y.Z --publish`:
   - archive a Release build (build number = commit count);
   - Developer ID export, signature check, notarize and staple the app and the DMG (built with
     [dmgbuild](https://github.com/dmgbuild/dmgbuild) from `scripts/dmg-settings.py`; the window background comes
     from `python3 Design/DMG/generate.py`; by hand you need `pipx install dmgbuild`);
   - sign the zip for Sparkle and write `appcast.xml`, with this version's `CHANGELOG.md` section embedded as the
     release notes the update window shows (`scripts/release-notes.py`);
   - upload the DMG, the zip, `appcast.xml` and the Homebrew cask (`triwarden.rb`) to the release;
   - push the cask to `Casks/triwarden.rb` in `sinhong2011/homebrew-tap`.
4. Installed copies with automatic checks on find the update through
   `https://github.com/sinhong2011/triwarden/releases/latest/download/appcast.xml`. They verify the EdDSA
   signature and the notarization, install, and relaunch. Everyone else gets it from **Check for Updates…**.

## One-time setup (maintainer)

These are your credentials, so run each step yourself. Nothing secret goes into the repository.

### 1. Update-signing key (Sparkle)

```bash
make sparkle-keys
```

This creates an EdDSA key pair in your login keychain and writes the **public** key to `project.yml`
(`SPARKLE_PUBLIC_KEY`). Commit that change. Back up the private key; without it, installed copies can't verify
any future update:

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
```

### 2. GitHub secrets for the `release` environment

Create an environment named `release` (Settings › Environments) and add the secrets:

| Secret | What |
| --- | --- |
| `DEVELOPER_ID_P12` | Your *Developer ID Application* certificate and key, exported as .p12, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | The .p12 export password |
| `ASC_KEY_P8` | An App Store Connect API key (Users and Access › Integrations; role *Admin* — creating Developer ID provisioning profiles needs it), the .p8 contents |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | That key's ID and the issuer ID |
| `SPARKLE_PRIVATE_KEY` | The contents of `sparkle-private-key.txt` from step 1 (then delete that file) |
| `HOMEBREW_TAP_DEPLOY_KEY` | The private half of a write deploy key on `sinhong2011/homebrew-tap` (see [Homebrew](#homebrew)) |

For example:

```bash
gh secret set DEVELOPER_ID_P12 --env release < <(base64 -i DeveloperID.p12)
gh secret set SPARKLE_PRIVATE_KEY --env release < sparkle-private-key.txt
```

The API key lets CI create the Developer ID provisioning profiles (App Group, AutoFill, Safari extension) and
notarize, without an Apple ID or password.

### 3. Licenses (Fork-style: paid, never locked)

Every feature works unregistered and there's no time limit. An unregistered official build asks at launch, no
more than once a week and never in the first week, whether the user wants to buy a license. Debug builds, and
any build without `TW_STORE_URL`, never ask.

Two kinds of key register (see `App/Sources/License.swift`):

- **Receipt keys**: Lemon Squeezy generates them and puts them in the receipt email, so you don't need to do
  anything. Pressing Register sends the key and a random install id to Lemon Squeezy once; nothing is checked
  after that.
- **Offline keys**: you sign them yourself, and they're checked on the Mac only. They're for buyers who'd rather
  nothing went online, and a fallback if Lemon Squeezy ever goes away.

1. In Lemon Squeezy, create **one** one-time product (License, **US$19.99**) with **license keys on, activation
   limit unlimited, and no expiry**. Removing a license in the app doesn't free an activation, so a limit would
   eventually lock buyers out. Turn on Alipay and WeChat Pay under Settings › Payments. Confirm the live price and
   checkout URL match before release (test-mode links must not be treated as live). In `project.yml`, set
   `TW_STORE_URL` / `TW_LEMON_PRODUCT_ID`, and optionally `TW_PRICING_URL` (absolute site `/pricing/`). Mirror the
   checkout link and price in `site/src/config.ts`.
2. Create the offline-key signing key:

   ```bash
   make license-keys
   ```

   This keeps an Ed25519 private key in your login keychain (`triwarden-license-signing`) and writes the public
   key to `project.yml` (`TW_LICENSE_PUBLIC_KEY`). Commit that change and back up the private key. If you lose
   it, you can't sign new offline keys that this build accepts.

3. When a buyer asks for an offline key, sign one for their order and email it to them:

   ```bash
   make license NAME="Usagi" EMAIL=usagi@example.com ORDER=1001
   ```

Either kind of key is for **one person** on all of their personal Macs (no device cap). Not for resale or
team sharing — see [LICENSE-TERMS.md](LICENSE-TERMS.md).

## Releasing by hand (fallback)

On your Mac, with an Xcode account for team `FX3VR69P5K` and notary credentials in your keychain:

```bash
xcrun notarytool store-credentials triwarden-notary --apple-id <you@example.com> --team-id FX3VR69P5K
scripts/release.sh 0.3.0 --publish
```

This uploads to the release `v0.3.0` if release-please made it, and creates the release otherwise. To try a local
build without notarizing or publishing: `ALLOW_DIRTY=1 scripts/release.sh 0.3.0 --skip-notarize`.

## Homebrew

Each release pushes its cask to `Casks/triwarden.rb` in
[sinhong2011/homebrew-tap](https://github.com/sinhong2011/homebrew-tap), using the `HOMEBREW_TAP_DEPLOY_KEY` secret
in the `release` environment: the private half of a deploy key that can write to that repository only. To replace
it, make a new key pair, add the public key to the tap under Settings › Deploy keys with write access, and store the
private key as that secret. Users run `brew install sinhong2011/tap/triwarden`. The cask also links `tw` onto the PATH. Homebrew users can update
with `brew upgrade` or in the app; both work.
