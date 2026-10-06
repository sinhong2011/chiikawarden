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
   - Developer ID export, signature check, notarize and staple the app and the DMG;
   - sign the zip for Sparkle and write `appcast.xml`;
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
