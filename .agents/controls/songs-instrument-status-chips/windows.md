# Instrument status chips — Windows notes

> **What:** Windows rendering of the selected-player chips on Songs rows. **Read when:** changing `SongRowVisuals.Chip` or `SongInstrumentStatusPolicy`. Rules: [spec.md](spec.md).

- Shown only via `SongInstrumentStatusPolicy.ShowsChips` (player, publication-matched scores, Show Instrument Icons on, no chart filter, Filter Invalid Scores off); one per visible chart in service order.
- 30 epx circle, status fill + stroke from BrandTokens (gold FC, green scored, red no score, amber inconsistent FC, muted at 45% opacity for not charted) with the 21 epx instrument icon (keys variant for Keyboard songs).
- Chips are `AccessibilityView.Raw` with a tooltip; the row's UIA name speaks every chart and status. Built in the phase-1 realization pass; inline from 760 epx list width, otherwise wrapped under the title.
