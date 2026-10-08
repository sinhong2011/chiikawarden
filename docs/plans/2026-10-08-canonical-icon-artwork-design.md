# Canonical icon artwork

## Goal

Use `Design/AppIcon/AppIcon.svg` as Triwarden's single authored icon across the website and in-app presentation.

## Design

`Design/AppIcon/generate.py` remains the authoring pipeline. It generates the SVG used by the website and the layered Icon Composer files that Xcode compiles into `AppIcon.icns` for macOS application and Dock integration.

The site will receive its public `assets/icon.svg` from the generated SVG rather than maintaining an independently copied drawing. The in-app About and licensing surfaces will display a bundled copy of that SVG directly, avoiding `NSApplication.shared.applicationIconImage`, whose result is supplied by Launch Services and can resolve a stale installed copy when several development builds share a bundle identifier.

The browser favicon and Apple-touch icon remain distinct delivery formats. The SVG favicon is canonical artwork; the PNG stays as the iOS-compatible touch icon.

## Verification

Regenerate the icon assets, build the macOS app and site, and verify that the website's icon has the same SHA-1 hash as the generated SVG. Confirm the app resource contains the SVG and the app compiles.
