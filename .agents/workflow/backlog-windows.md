# Windows backlog

> **What:** queued Windows-only work while the Windows host is reserved. **Read when:** planning Windows lanes once the host is free. Shared items: [android-windows-backlog.md](android-windows-backlog.md).

## Queue

| Item | Source | Notes |
|---|---|---|
| Operator Narrator walkthrough (script in [windows.md](../testing/windows.md)) | win-a11y | Needs the operator; contrast-theme colours decided by win-unify ([design/windows.md](../design/windows.md)) |
| Notification badge at real 100% / 200% DPI | win-chrome | Only 150% verified; the host has no 100%/200% display (needs a monitor or remote session at that scale) |

## Done

| Item | Where |
|---|---|
| Band rank history chart (bar + line, paging) | win-shell2 |
| Leaderboards wide preset Axe clipping | win-next a11y pass ([windows-accessibility](../testing/windows-accessibility.md)) |
| GlobalSearch players-freeze flake | win-next `ad9cad99`: status reported before the state settles |
| Stale `fst.song-detail.shop-badge` in `contracts/product.json` | win-next `6a4a1033` |
| Sticky Songs section headers without show-through | win-shell2 |
| Leaderboards Spotlight "Loading your rank…" caption | win-polish (ring only; UIA name kept) |
| First-run demos; What's New launch-order journey | win-pwa / win-shell2 (`tools/windows/journeys/whats-new.json`) |
| PWA gaps 18–19 (background presets, entrance motion) | win-next (web `MOTION_PRESETS`) / win-polish (`FadeIn`) |
| Release/AOT journey pass for the new pages | win-shell2 `65525206` |
| Two populated columns: Songs, Full Rankings, Band Rankings, All Rivals | win-shell2 / win-next `070f4ea0` (Rivals hub: masonry columns) |
| Expanded NavigationView pane (no title in the pane, first item aligned with the page title, transparent) | Verified 2026-09-29 (no repro) |
| Web-parity Songs filter (6.32 / 7.17) | win-next `cd06f0b1` |
| Paths journeys after `7f45f884` | win-next `cd06f0b1`, `6a4a1033` |
