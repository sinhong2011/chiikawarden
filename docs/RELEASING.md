# Releasing

Releases are Developer ID–signed, notarized, and published as a DMG and a zip on GitHub, plus a Homebrew cask.

## One-time setup (maintainer's Mac)

1. **Xcode account.** Xcode › Settings › Accounts › add the Apple ID of team `FX3VR69P5K`. Exporting needs it to
   create the *Developer ID* provisioning profiles for the App Group, the AutoFill credential provider and the Safari
   extension. Without it, the export fails with “No Accounts”.
2. **Notary credentials.** Use an app-specific password; it's stored only in your login keychain:
   ```bash
   xcrun notarytool store-credentials chiikawarden-notary --apple-id <you@example.com> --team-id FX3VR69P5K
   ```
3. `brew install xcodegen gh`, and `gh auth login` as an account that can push to the repo.

## Each release

```bash
scripts/release.sh 0.3.0 --publish
```

The script:
1. archives a Release build (version 0.3.0, build number = commit count);
2. exports it with Developer ID and checks the signature;
3. notarizes and staples the app, then the DMG;
4. writes `dist/<version>/Chiikawarden-<version>.dmg`, the zip, and `chiikawarden.rb` (the Homebrew cask);
5. with `--publish`, tags `v<version>` and creates a **draft** GitHub release with the DMG and zip. Review the notes
   and publish it by hand.

For a local dry run without notarization: `ALLOW_DIRTY=1 scripts/release.sh 0.3.0 --skip-notarize`.

## Homebrew

Copy `dist/<version>/chiikawarden.rb` to `Casks/chiikawarden.rb` in the `sinhong2011/homebrew-tap` repository. Users then
run `brew install sinhong2011/tap/chiikawarden`. The cask also links `cw` onto the PATH.

## Updates

Chiikawarden checks GitHub's latest release only if the user turns it on (Settings › General › Check for updates). It
compares versions and links to the release page; it never downloads or installs anything by itself.
