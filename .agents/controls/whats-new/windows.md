# What's New changelog — Windows notes

> **What:** the WinUI What's New dialog, its launch gate and Settings replay as built. **Read when:** changing the changelog content, gate or dialog on Windows. Spec: [spec.md](spec.md); iPhone: [ios.md](ios.md).

## Implementation

| Piece | Where |
|---|---|
| Entries, web hash, Title Case, Manual filter | `Festival.Core/Domain/Changelog.cs` (`Changelog`, `WhatsNewGate`, `WhatsNewMode`); `WhatsNewTests.Hash_MatchesTheWebsPrecomputedHash` pins `-6p8bh3` |
| Dismissal record | `Data/ChangelogSeenStore.cs` → `whats-new.json` in the app data folder (`AppStateFiles.WhatsNew`, kept by Settings Reset); `{version, hash}` ≤ 1 KB, hash ≤ 32, version ≤ 64; invalid → show again |
| Dialog | `Festival.App/MainWindow.WhatsNew.cs`: `ContentDialog` "What's New · <app version>", Title Case level-2 headings with bullets in a scroller, **Dismiss** (close button; Esc also dismisses and records). IDs `fst.whats-new.dialog`, `fst.whats-new.list` |
| Replay | Settings → Version → **What's New · Show** (`fst.settings.whats-new`) → `MainWindow.ShowWhatsNew()` |

## Gate and ordering

- Checked 700 ms after launch so the first page's first-run carousel claims the dialog slot first; `MainWindow.ShowDialogAsync` serializes ContentDialogs, so What's New follows a carousel and a later carousel waits for it. Never presented into a minimized/hidden window (retries).
- `--whats-new off|on|fresh|force` (or `FST_DEBUG_WHATS_NEW` in Debug/automation launches): Debug and automation default **off**, Release normal; `fresh` forgets the dismissal once.

## Open

- Live screenshots: `showcase\win-pwa\live\`. UIA journey for launch order not yet scripted.
