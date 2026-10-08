# Benchmarks

How quickly Triwarden opens, how little memory it keeps, and how long an unlock takes, measured on one Mac by
`make bench` (`scripts/bench.sh`). Re-run it on yours: numbers depend on the machine, and on what else it's doing.

## Triwarden 0.1.1 (8e70413)

2026-10-08 · Apple M4 Pro (Mac16,11), 64 GB · macOS 27.0.1 · Debug build with Swift optimisation (-O) · demo vault of 200+ items

| Measure | Median | Range | Notes |
| --- | ---: | ---: | --- |
| Launch to first frame | 866 ms | 849–1354 ms | 5 fresh launches; from the kernel starting the process |
| Launch to vault ready | 867 ms | 849–1354 ms | the item list on screen with items in it |
| Memory at idle | 138 MB | | phys_footprint (Activity Monitor's “Memory”) after 10 s idle, vault open |
| Master-password unlock, PBKDF2 600,000 | 89 ms | | key derivation + user key decryption, median of 5 |
| Master-password unlock, Argon2id 64 MiB · 3 · 4 | 140 ms | | Bitwarden's default Argon2id settings, median of 5 |

Touch ID can't be timed without a finger: `scripts/bench.sh --interactive 5` opens the app on your own accounts and
times five real unlocks (from the moment Touch ID approves, or Return is pressed, to the vault on screen).

## Measuring the Bitwarden desktop app by hand

We can't script someone else's app, so these steps give comparable numbers by hand. Use the same Mac, quit other
apps, and take the median of five tries. Please don't publish numbers you didn't measure.

1. **Launch to window.** Quit Bitwarden (⌘Q). Start a screen recording (⇧⌘5), click Bitwarden in the Dock, and
   count frames from the click to the window's first frame (QuickTime Player steps a frame at a time with ← →).
   Do the same for Triwarden for a like-for-like number.
2. **Launch to vault ready.** With the vault unlocked at quit (or "Never lock"), count frames until the item list is
   filled.
3. **Memory at idle.** Unlock, leave it 10 seconds, then add up every Bitwarden process — Electron runs a main
   process, a GPU process and one or more renderers:
   ```bash
   for p in $(pgrep -f Bitwarden); do footprint -p $p | awk '/Footprint:/'; done
   ```
   Activity Monitor's Memory column shows the same figure per process; sum the Bitwarden ones.
4. **Unlock.** Lock the vault, then time from pressing Return on the master password (or touching the sensor) to the vault
   on screen, again by counting video frames. Note the account's KDF (Settings › Security › Keys in the web vault):
   PBKDF2 and Argon2id take very different times, in any app.

Record the app version, the Mac and macOS version with your numbers.
