#!/usr/bin/env bash
# Build a signed, notarized Triwarden release.
#
#   scripts/release.sh 0.3.0            # archive, Developer ID export, notarize, staple, zip + dmg
#   scripts/release.sh 0.3.0 --publish  # …and create the GitHub release (draft) with the artifacts
#   scripts/release.sh 0.3.0 --skip-notarize   # local dry run
#
# Normally CI runs this when a release-please PR is merged (.github/workflows/release.yml); it uploads to the
# release that release-please created. Run it by hand only as a fallback.
#
# Signing in to Apple, either:
#   local: your Xcode account + `xcrun notarytool store-credentials triwarden-notary --apple-id … --team-id FX3VR69P5K`
#   CI:    an App Store Connect API key: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
# Sparkle update signature: the EdDSA private key from your keychain (`make sparkle-keys`), or SPARKLE_KEY_FILE in CI.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version> [--publish] [--skip-notarize]}
shift
PUBLISH=0; NOTARIZE=1
for arg in "$@"; do
  case $arg in --publish) PUBLISH=1 ;; --skip-notarize) NOTARIZE=0 ;; *) echo "unknown option $arg"; exit 64 ;; esac
done
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3"; exit 64; }
PROFILE=${NOTARY_PROFILE:-triwarden-notary}
# App Store Connect API key (CI): lets xcodebuild fetch Developer ID profiles and notarytool submit, without an Apple ID.
AUTH=(); NOTARY=(--keychain-profile "$PROFILE")
if [[ -n ${ASC_KEY_PATH:-} ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  NOTARY=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
fi
BUILD=$(git rev-list --count HEAD)
OUT=dist/$VERSION
ARCHIVE=$OUT/Triwarden.xcarchive
rm -rf "$OUT" && mkdir -p "$OUT"

[[ -n ${ALLOW_DIRTY:-} || -z $(git status --porcelain) ]] || { echo "working tree not clean"; exit 1; }

echo "== Generate project"
xcodegen generate -q

echo "== Archive $VERSION ($BUILD)"
xcodebuild -project Triwarden.xcodeproj -scheme Triwarden -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates "${AUTH[@]}" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

echo "== Export with Developer ID"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>FX3VR69P5K</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates "${AUTH[@]}" | grep -E "error:|EXPORT (SUCCEEDED|FAILED)"
APP=$OUT/export/Triwarden.app

KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist" 2>/dev/null || true)
[[ -n $KEY ]] || { echo "SUPublicEDKey is empty: run 'make sparkle-keys' once and commit project.yml"; exit 1; }

echo "== Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier"

ZIP=$OUT/Triwarden-$VERSION.zip
DMG=$OUT/Triwarden-$VERSION.dmg
if [[ $NOTARIZE == 1 ]]; then
  echo "== Notarize (profile $PROFILE)"
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" "${NOTARY[@]}" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
fi

echo "== Package"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGE=$OUT/dmg && mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Triwarden $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [[ $NOTARIZE == 1 ]]; then
  xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait
  xcrun stapler staple "$DMG"
fi
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

echo "== Homebrew cask"
cat > "$OUT/triwarden.rb" <<CASK
cask "triwarden" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/sinhong2011/triwarden/releases/download/v#{version}/Triwarden-#{version}.dmg"
  name "Triwarden"
  desc "Native macOS client for Vaultwarden and Bitwarden"
  homepage "https://github.com/sinhong2011/triwarden"

  depends_on macos: ">= :tahoe"

  app "Triwarden.app"
  binary "#{appdir}/Triwarden.app/Contents/MacOS/tw"

  zap trash: [
    "~/Library/Group Containers/FX3VR69P5K.io.github.sinhong2011.triwarden",
    "~/Library/Containers/io.github.sinhong2011.triwarden",
  ]
end
CASK

echo "== Sparkle appcast"
# Signs the zip with the EdDSA key and writes appcast.xml pointing at this release's download.
SPARKLE_BIN=${SPARKLE_BIN:-$(find build/SourcePackages/artifacts ~/Library/Developer/Xcode/DerivedData -path "*sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)}
[[ -x $SPARKLE_BIN/generate_appcast ]] || { echo "Sparkle tools not found; build once (make build) or set SPARKLE_BIN"; exit 1; }
FEED=$OUT/feed && mkdir -p "$FEED" && cp "$ZIP" "$FEED/"
KEY_ARGS=(); [[ -n ${SPARKLE_KEY_FILE:-} ]] && KEY_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/sinhong2011/triwarden/releases/download/v$VERSION/" \
  --full-release-notes-url "https://github.com/sinhong2011/triwarden/releases/tag/v$VERSION" \
  --link "https://github.com/sinhong2011/triwarden" "$FEED"
cp "$FEED/appcast.xml" "$OUT/appcast.xml"
grep -q 'sparkle:edSignature' "$OUT/appcast.xml" || { echo "appcast is not signed"; exit 1; }

if [[ $PUBLISH == 1 ]]; then
  [[ $NOTARIZE == 1 ]] || { echo "refusing to publish an un-notarized build"; exit 1; }
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "== Upload to release v$VERSION"   # created by release-please
  else
    echo "== GitHub release v$VERSION"
    gh release create "v$VERSION" --title "Triwarden $VERSION" --generate-notes
  fi
  gh release upload "v$VERSION" "$DMG" "$ZIP" "$OUT/appcast.xml" "$OUT/triwarden.rb" --clobber
fi

echo
echo "Done: $OUT"
ls -lh "$OUT" | grep -E "\.(dmg|zip|rb|xml)$"
echo "sha256 $SHA"
