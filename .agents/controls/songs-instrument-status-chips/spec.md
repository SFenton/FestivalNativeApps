# Selected-player instrument status chips (`fst.songs.instrument-status.*`) — spec

> **What:** when the per-chart status chips show on a Songs row, how each status is derived and cued, and native safety deviations. **Read when:** changing selected-player Songs rows with icons on, on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:190-200,251-271,455-535,548-549`, `FortniteFestivalWeb/src/components/display/InstrumentIcons.tsx:38-51,93-122`, `FortniteFestivalWeb/src/pages/songs/layoutMode.ts:14-81`, `FortniteFestivalWeb/src/contexts/SettingsContext.tsx:55-93`, `packages/theme/src/colors.ts:15-68`, `packages/theme/src/spacing.ts:120-127`.

## When chips show

One chip per **enabled** solo chart, in the service's stable nine-chart order, only when: an explicitly selected player's public 200 scores are available, Show Instrument Icons is on, Songs is not filtered to one chart, and Filter Invalid Scores is off. Derive ≤9 statuses from the existing validated per-song score index — no extra GET, no selected-profile headers, no raw profile bytes across accounts, never for bands. Otherwise use the [metadata](../song-score-metadata/spec.md) presentation.

## Status rules

| Status | Cue and spoken state | Rule |
|---|---|---|
| Not charted | Muted circle, slash; "not charted" | Song difficulty missing, non-finite, negative or 99 — **even if** a score exists |
| Full combo | Gold circle, star; "full combo" | Charted, score > 0, explicit FC |
| Scored | Green circle, check; "scored" | Charted, positive score, no FC |
| No score | Red circle, minus; "no score" | Charted, no row, or zero score without FC |
| Inconsistent FC | Red circle, exclamation; "score missing despite a reported full combo" | Charted, zero score with explicit FC (web paints gold: native safety deviation) |

- An available 200 with no scores is not a 202: charted parts read "no score", uncharted "not charted".
- Loading, 202, error and publication changes keep their explicit score state **without chips** (the web's 202 red-chip behavior is inferred from code, not observed).
- Retained older Songs rows after a failed refresh never get newer chips: each row says "Player scores paused until songs update" and the list has a separate pause notice.
- The combined row link speaks every enabled chart and status in order — not nine tiny separate actions. Each status has a distinct shape; colour is never the only cue.
- Web layout: 390px phone wraps nine chips 5+4; 820px tablet shows one row.
- Tokens: glyph/mark ≥4.5:1 on the opaque fill, unavailable outline and red boundary ≥3:1 on the card (`python3 -m tools.contrast_gate`); this is not rendered-screenshot proof.
