# macOS 15 compatibility audit

Date: 2026-10-10

## Conclusion

Supporting macOS 15 appears feasible with a small toolbar compatibility change. An isolated copy of the current working tree compiled successfully for an arm64 Debug build with a minimum deployment target of macOS 15. This is compile-time evidence, not a macOS 15 runtime certification. The production project and website requirements remain macOS 26.

## Confirmed blockers

- `project.yml` sets the global minimum to macOS 26.0.
- `Packages/VaultCore/Package.swift` declares `.macOS(.v26)`.
- `App/Sources/VaultView.swift` uses `sharedBackgroundVisibility(.hidden)` twice and `ToolbarSpacer(.flexible)` once without availability guards. These require macOS 26.

The initial build with only the minimum versions lowered failed on those toolbar APIs and a SwiftUI type-check timeout. Removing the three toolbar uses in the isolated copy allowed the full app scheme to build successfully. This removal was an audit experiment, not a finished fallback design.

No direct `glassEffect` or `GlassEffectContainer` use was found in the app, shared code, or AutoFill extension.

## Core capabilities

The installed Apple SDK headers mark the currently used OTP provider entry point and ASOneTimeCodeCredential as available on macOS 15. Passkey provider entry points are available from macOS 14; the excludedCredentials property used by registration is available from macOS 15. ASSettingsHelper is available from macOS 14. Thus, this audit found no reason to remove these capabilities solely to target macOS 15.

Reference: https://developer.apple.com/documentation/authenticationservices/asonetimecodecredential
Reference: https://developer.apple.com/documentation/authenticationservices/assettingshelper

## Validation performed

In `/tmp/triwarden-macos15-audit`, copied the current working tree, lowered the project and package minimums to 15, removed the three toolbar uses, generated the Xcode project, and built:

```sh
xcodebuild -project /tmp/triwarden-macos15-audit/Triwarden.xcodeproj \
  -scheme Triwarden -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/triwarden-macos15-audit-build \
  CODE_SIGNING_ALLOWED=NO build
```

Result: BUILD SUCCEEDED. Built Info.plists report LSMinimumSystemVersion 15.0 for Triwarden, AutoFill, Safari extension, and Auto-Type helper. Logs: `/tmp/triwarden-macos15-audit-build.log` and `/tmp/triwarden-macos15-audit-build-fallback.log`.

## Recommended implementation and release gate

1. Lower both minimum versions together. Keep the current toolbar appearance on macOS 26 with availability branches; supply a standard toolbar layout on macOS 15.
2. Build Debug and the release architecture configuration. Verify legacy icon output on macOS 15; the Icon Composer source is not runtime validation.
3. Test on an actual macOS 15 installation or VM: launch, login, sync, lock/unlock, Touch ID/master password, Keychain persistence, create/edit/search, Command Palette, clipboard expiry, Auto-Type permissions, password/OTP/passkey AutoFill, Safari extension, SSH approval, and Sparkle updates. Check light/dark and narrow-window layouts.
4. Update README and the five site translations only after runtime validation. Keep build toolchain requirements distinct from end-user minimum OS requirements.
5. Keep modern Xcode for builds; add macOS 15 runtime coverage where the CI environment supports it. Current CI only runs on macos-26.

Not validated: macOS 15 runtime behavior, signed/notarized release, Intel build/runtime, legacy app icon appearance, or updater behavior on macOS 15.
