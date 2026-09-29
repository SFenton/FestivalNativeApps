# What's New changelog — Windows notes

> **What:** the WinUI What's New dialog, its launch gate and Settings replay as built. **Read when:** changing the changelog content, gate or dialog on Windows. Spec: [spec.md](spec.md); iPhone: [ios.md](ios.md).

## Implementation

| Piece | Where |
|---|---|
| Entries, web hash, Title Case, Manual filter | `Festival.Core/Domain/Changelog.cs` (`Changelog`, `WhatsNewGate`, `WhatsNewMode`); `WhatsNewTests.Hash_MatchesTheWebsPrecomputedHash` pins `-6p8bh3` |
| Dismissal record | `Data/ChangelogSeenStore.cs` → `whats-new.json` in the app data folder (`AppStateFiles.WhatsNew`, kept by Settings Reset); `{version, hash}` ≤ 1 KB, hash ≤ 32, version ≤ 64; invalid → show again |
| Dialog | `Festival.App/MainWindow.WhatsNew.cs`: `ContentDialog` "What's New · <app version>", Title Case level-2 headings with bullets in a scroller, **Dismiss** (close button spanning the command row, centred like the web's full-width button; Esc and a click outside also dismiss and record; operator batch 6.14). IDs `fst.whats-new.dialog`, `fst.whats-new.list` |
| Replay | Settings → Version → **What's New · Show** (`fst.settings.whats-new`) → `MainWindow.ShowWhatsNew()` |

## Gate and ordering

- Checked 700 ms after launch (the timer lives in a field: until 2026-09-28 it was a local that was collected before firing, so the launch dialog never appeared) so the first page's first-run carousel claims the dialog slot first; `MainWindow.ShowDialogAsync` serializes ContentDialogs, so What's New follows a carousel and a later carousel waits for it. Never presented into a minimized/hidden window (retries).
- `--whats-new off|on|fresh|force` (or `FST_DEBUG_WHATS_NEW` in Debug/automation launches): Debug and automation default **off**, Release normal; `fresh` forgets the dismissal once.

## Open

- Live screenshots: `showcase\win-pwa\live\`, `showcase\win-shell2\live\`. Launch order verified by hand (carousel, then What's New); UIA journey for it not yet scripted.
