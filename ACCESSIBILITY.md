# Accessibility

Chiikawarden should work fully with VoiceOver, with the keyboard alone, and for people with low vision.
If something gets in your way, please [open an issue](https://github.com/sinhong2011/chiikawarden/issues)
with the `accessibility` label.

## VoiceOver

- The sidebar, settings, edit sheet and login form are standard SwiftUI controls, so they read with their
  visible labels.
- Every icon-only button has a spoken label: favorite, edit, trash, restore, delete forever, lock,
  reveal/hide, copy *field*, generate password, remove field, clear search, retry Touch ID, open item.
- Vault rows, Quick Search results and AutoFill rows read as one element (name, then username or site),
  with the button trait. The selected vault row also has the selected trait.
- Watchtower and password strength never rely on colour alone. Each colour dot has a text label
  (“Weak”, “Reused in 2 items”, “Strong · unique”).
- Secrets are hidden by default and announced as secure text until you choose Reveal.

## Keyboard

| Action | Keys |
|---|---|
| Search or run a command | ⌘K or ⌘F |
| Move through items | ↑ / ↓ in the item list |
| New login / secure note / folder | ⌘N / ⇧⌘N / ⌥⌘N |
| Edit item | ⌘E |
| Move to Trash | ⌘⌫ |
| Password generator | ⌘G |
| Command palette from anywhere | ⌘K by default (Settings › General › Shortcuts), then ↑ / ↓, ↵ open, ⌘↵ password, ⌥↵ code, Esc to close |
| AutoFill picker | type to search, ↑ / ↓, Return to fill or sign in |
| Lock | ⇧⌘L |
| Sheets and dialogs | Return confirms, Esc cancels |

With Full Keyboard Access on (System Settings › Keyboard › Keyboard navigation), Tab reaches every control.

## Contrast

The brand colour is the sky blue of the mascot's tail (tint #CBE4F6), deepened until it meets WCAG 2.2 AA
(relative-luminance formula):

| Use | Light | Dark |
|---|---|---|
| Blue text / links on the window background | #2371A9 on #F2F2F7: **4.70:1** | #47A0E1 on #1E1E1E: **5.86:1** |
| Blue text on panels | #2371A9 on #FFFFFF: **5.24:1** | #47A0E1 on #2C2C2E: **4.90:1** |
| White text on blue buttons | **5.24:1** | **2.84:1** (below AA; see known gaps) |

The pale tail tint itself is only used for washes and soft fills, never for text.
All other text uses system semantic colours (`.primary`, `.secondary`), which follow macOS Increase Contrast.

## Motion

The animated dial on the login screen stops when **Reduce Motion** is on.

## Known gaps

- Short UI transitions (list changes, the toast, sheet content) still animate with Reduce Motion on.
- White on the dark-mode sky blue is 2.84:1, under AA. Prominent buttons in dark mode should move to dark
  label text; tracked as a follow-up.
- There is no automated accessibility test yet. Checks so far are code review plus snapshot review.
  A VoiceOver walkthrough on real hardware is tracked in the issues.
