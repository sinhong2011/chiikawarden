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
| Search the vault | ⌘F |
| Move through items | ↑ / ↓ in the item list |
| New login / secure note / folder | ⌘N / ⇧⌘N / ⌥⌘N |
| Edit item | ⌘E |
| Move to Trash | ⌘⌫ |
| Password generator | ⌘G |
| Quick Search from anywhere | ⌥Space, then ↑ / ↓, Return to copy, Esc to close |
| AutoFill picker | type to search, ↑ / ↓, Return to fill or sign in |
| Lock | ⇧⌘L |
| Sheets and dialogs | Return confirms, Esc cancels |

With Full Keyboard Access on (System Settings › Keyboard › Keyboard navigation), Tab reaches every control.

## Contrast

The brand blue was tuned to meet WCAG 2.2 AA (checked with the WCAG relative-luminance formula):

| Use | Light | Dark |
|---|---|---|
| Blue text / chips on the window background | #3A63E8 on #F2F2F7: **4.56:1** | #6390FF on #1E1E1E: **5.53:1** |
| Blue text on panels | #3A63E8 on #FFFFFF: **5.08:1** | #6390FF on #2C2C2E: **4.62:1** |
| White text on blue buttons | **5.08:1** | **3.02:1** (AA for large/bold text only) |

All other text uses system semantic colours (`.primary`, `.secondary`), which follow macOS Increase Contrast.

## Motion

The animated dial on the login screen stops when **Reduce Motion** is on.

## Known gaps

- Short UI transitions (list changes, the toast, sheet content) still animate with Reduce Motion on.
- White on the dark-mode blue (3.02:1) meets AA only for large or bold text. Prominent buttons use semibold
  13 pt labels, which is just under the “large text” size.
- There is no automated accessibility test yet. Checks so far are code review plus snapshot review.
  A VoiceOver walkthrough on real hardware is tracked in the issues.
