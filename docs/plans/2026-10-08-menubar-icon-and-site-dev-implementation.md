# Menu-bar Icon and Site Dev Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give Triwarden a readable, aligned vault-dial menu-bar glyph and start the Astro site through a root Makefile target.

**Architecture:** Keep the menu-bar image as a code-drawn monochrome AppKit template in `MenuBarGlyph`, preserving all scene wiring and lock-state behaviour. Add one foreground `site` Make target that delegates to the existing package script.

**Tech Stack:** SwiftUI, AppKit, GNU Make, pnpm, Astro.

---

### Task 1: Replace the menu-bar glyph geometry

**Files:**
- Modify: `App/Sources/MenuBarExtraView.swift:644-677`
- Test: `make build`

**Step 1: Establish the expected source shape**

Add the three aligned dial radii as the intended invariant in `MenuBarGlyph`:

```swift
for radius: CGFloat in [5.6, 4.0, 2.45] {
    // Each arc opens at six o’clock.
}
```

**Step 2: Verify the pre-change build succeeds**

Run: `make build`

Expected: `BUILD SUCCEEDED`.

**Step 3: Implement the compact dial**

Replace the offset two-ring loop with three concentric, six-o’clock-open arcs. Retain a thin outer bezel and centre the existing solid keyhole. Keep `image.isTemplate = true` and its accessibility description unchanged.

**Step 4: Verify the app build**

Run: `make build`

Expected: `BUILD SUCCEEDED`.

**Step 5: Verify in the native UI**

Run: `make run`

Expected: Triwarden launches and its menu-bar glyph is a clean monochrome vault dial in both the locked and unlocked opacity states.

**Step 6: Commit**

```bash
git add App/Sources/MenuBarExtraView.swift
git commit -m "feat: simplify menu bar vault glyph"
```

### Task 2: Add the root website development target

**Files:**
- Modify: `Makefile:13, 19-22`
- Test: `make -n site`

**Step 1: Add the target to the phony declaration**

Add `site` to `.PHONY` so a file named `site` can never suppress the command.

**Step 2: Add the failing target invocation check**

Run: `make -n site`

Expected before implementation: `make: *** No rule to make target 'site'.  Stop.`

**Step 3: Implement the target**

Add this command immediately after `run`:

```make
site: ## Run the website development server
	@pnpm --dir site dev --port 4321
```

**Step 4: Verify the command expansion**

Run: `make -n site`

Expected: `pnpm --dir site dev --port 4321`.

**Step 5: Commit**

```bash
git add Makefile
git commit -m "build: add website development target"
```

### Task 3: Final verification

**Files:**
- Verify: `App/Sources/MenuBarExtraView.swift`
- Verify: `Makefile`

**Step 1: Build the application**

Run: `make build`

Expected: `BUILD SUCCEEDED`.

**Step 2: Verify the site command**

Run: `make -n site`

Expected: exactly one `pnpm --dir site dev --port 4321` command.

**Step 3: Inspect the diff**

Run: `git diff --check HEAD~2..HEAD`

Expected: no whitespace errors.
