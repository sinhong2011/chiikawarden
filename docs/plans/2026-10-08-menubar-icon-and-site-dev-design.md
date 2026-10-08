# Menu-bar icon and site dev command

## Goal

Make Triwarden’s menu-bar icon legible at its 18-point template size and expose the website’s existing Astro development server through `make`.

## Menu-bar glyph

Replace the offset two-ring mark with a compact vault dial that echoes the redesigned application icon:

- a single fine outer bezel establishes the dial silhouette;
- three progressively shorter, concentric arcs share a six-o’clock opening;
- a small, solid keyhole remains centred, providing the security cue at glance size;
- the glyph remains a monochrome `NSImage` template so macOS supplies the correct menu-bar colour and locked opacity continues to work unchanged.

The illustration stays programmatic in `MenuBarGlyph`: no raster resource, new dependency, state, or accessibility change is needed.

## Website development command

Add a phony `site` target to the root Makefile. It runs `pnpm --dir site dev --port 4321`, matching the checked-in launch configuration and the website README. It intentionally remains foregrounded so Astro preserves its normal live-reload lifecycle and terminal output.

## Verification

Build the macOS app with `make build` and run it to inspect the menu-bar template in its native context. Run `make -n site` to assert the root command expands to the expected Astro invocation without starting a long-lived server.
