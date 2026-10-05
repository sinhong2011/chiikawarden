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

The brand colour is the sky blue of the mascot's tail, #80C5EF. It is used as a **fill** (buttons, the vault mark,
selection) with navy text, and a deeper vivid sky carries blue **text** where it has to be readable on light
backgrounds (WCAG 2.2 AA, relative-luminance formula):

| Use | Light | Dark |
|---|---|---|
| Navy text on tail-blue buttons | #0B2A40 on #80C5EF: **7.86:1** | same |
| Blue text / links / icons | #0F74B3 on #F2F2F7: **4.51:1** (5.04:1 on white) | #80C5EF on #1E1E1E: **8.85:1** |
| White text on system prominent buttons | on #0F74B3: **5.04:1** | on #80C5EF: below AA (see known gaps) |

All other text uses system semantic colours (`.primary`, `.secondary`), which follow macOS Increase Contrast.

## Motion

The animated dial on the login screen stops when **Reduce Motion** is on.

## Known gaps

- Short UI transitions (list changes, the toast, sheet content) still animate with Reduce Motion on.
- System `.borderedProminent` buttons (e.g. Save in sheets) draw white text on the accent; in dark mode that is
  under AA on the tail sky. Chiikawarden's own primary buttons use navy text instead; the system ones are a follow-up.
- There is no automated accessibility test yet. Checks so far are code review plus snapshot review.
  A VoiceOver walkthrough on real hardware is tracked in the issues.
