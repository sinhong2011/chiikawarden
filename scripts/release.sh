#!/usr/bin/env bash
# Build a signed, notarized Chiikawarden release.
#
#   scripts/release.sh 0.3.0            # archive, Developer ID export, notarize, staple, zip + dmg
#   scripts/release.sh 0.3.0 --publish  # …and create the GitHub release (draft) with the artifacts
#   scripts/release.sh 0.3.0 --skip-notarize   # local dry run
#
# One-time setup (your Apple ID; stored in your login keychain, never in this repo):
#   xcrun notarytool store-credentials chiikawarden-notary --apple-id <you@example.com> --team-id FX3VR69P5K
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version> [--publish] [--skip-notarize]}
shift
PUBLISH=0; NOTARIZE=1
for arg in "$@"; do
  case $arg in --publish) PUBLISH=1 ;; --skip-notarize) NOTARIZE=0 ;; *) echo "unknown option $arg"; exit 64 ;; esac
done
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3"; exit 64; }
PROFILE=${NOTARY_PROFILE:-chiikawarden-notary}
BUILD=$(git rev-list --count HEAD)
OUT=dist/$VERSION
ARCHIVE=$OUT/Chiikawarden.xcarchive
rm -rf "$OUT" && mkdir -p "$OUT"

[[ -n ${ALLOW_DIRTY:-} || -z $(git status --porcelain) ]] || { echo "working tree not clean"; exit 1; }

echo "== Generate project"
xcodegen generate -q

echo "== Archive $VERSION ($BUILD)"
xcodebuild -project Chiikawarden.xcodeproj -scheme Chiikawarden -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates \
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
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates | grep -E "error:|EXPORT (SUCCEEDED|FAILED)"
APP=$OUT/export/Chiikawarden.app

echo "== Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier"

ZIP=$OUT/Chiikawarden-$VERSION.zip
DMG=$OUT/Chiikawarden-$VERSION.dmg
if [[ $NOTARIZE == 1 ]]; then
  echo "== Notarize (profile $PROFILE)"
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
fi

echo "== Package"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGE=$OUT/dmg && mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Chiikawarden $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [[ $NOTARIZE == 1 ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

echo "== Homebrew cask"
cat > "$OUT/chiikawarden.rb" <<CASK
cask "chiikawarden" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/sinhong2011/chiikawarden/releases/download/v#{version}/Chiikawarden-#{version}.dmg"
  name "Chiikawarden"
  desc "Native macOS client for Vaultwarden and Bitwarden"
  homepage "https://github.com/sinhong2011/chiikawarden"

  depends_on macos: ">= :tahoe"

  app "Chiikawarden.app"
  binary "#{appdir}/Chiikawarden.app/Contents/MacOS/cw"

  zap trash: [
    "~/Library/Group Containers/FX3VR69P5K.io.github.sinhong2011.chiikawarden",
    "~/Library/Containers/io.github.sinhong2011.chiikawarden",
  ]
end
CASK

if [[ $PUBLISH == 1 ]]; then
  [[ $NOTARIZE == 1 ]] || { echo "refusing to publish an un-notarized build"; exit 1; }
  echo "== GitHub release (draft)"
  git tag -a "v$VERSION" -m "Chiikawarden $VERSION"
  git push origin "v$VERSION"
  gh release create "v$VERSION" "$DMG" "$ZIP" --draft --title "Chiikawarden $VERSION" --generate-notes
fi

echo
echo "Done: $OUT"
ls -lh "$OUT" | grep -E "\.(dmg|zip|rb)$"
echo "sha256 $SHA"
