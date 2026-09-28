# Selected-player instrument status chips (`fst.songs.instrument-status.*`) — spec

> **What:** when the per-chart status chips show on a Songs row, how each status is derived and cued, and native safety deviations. **Read when:** changing selected-player Songs rows with icons on, on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:190-200,251-271,455-535,548-549`, `FortniteFestivalWeb/src/components/display/InstrumentIcons.tsx:38-51,93-122`, `FortniteFestivalWeb/src/pages/songs/layoutMode.ts:14-81`, `FortniteFestivalWeb/src/contexts/SettingsContext.tsx:55-93`, `packages/theme/src/colors.ts:15-68`, `packages/theme/src/spacing.ts:120-127`.

## When chips show

One chip per **enabled** solo chart, in the service's stable nine-chart order, only when: an explicitly selected player's public 200 scores are available, Show Instrument Icons is on, Songs is not filtered to one chart, and Filter Invalid Scores is off. Derive ≤9 statuses from the existing validated per-song score index — no extra GET, no selected-profile headers, no raw profile bytes across accounts, never for bands. Otherwise use the [metadata](../song-score-metadata/spec.md) presentation.

## Status rules

| Status | Cue and spoken state | Rule |
|---|---|---|
| Not charted | Muted circle; "not charted" | Song difficulty missing, non-finite, negative or 99 — **even if** a score exists |
| Full combo | Gold circle; "full combo" | Charted, score > 0, explicit FC |
| Scored | Green circle; "scored" | Charted, positive score, no FC |
| No score | Red circle; "no score" | Charted, no row, or zero score without FC |
| Inconsistent FC | Amber circle; "score missing despite a reported full combo" | Charted, zero score with explicit FC (web paints gold; native uses a fifth, unshared color — see below) |

- An available 200 with no scores is not a 202: charted parts read "no score", uncharted "not charted".
- Loading, 202, error and publication changes keep their explicit score state **without chips** (the web's 202 red-chip behavior is inferred from code, not observed).
- Retained older Songs rows after a failed refresh never get newer chips: each row says "Player scores paused until songs update" and the list has a separate pause notice.
- The combined row link speaks every enabled chart and status in order — not nine tiny separate actions.
- **Native deviation (2026-09-28, operator request):** the former star/check/minus/exclamation corner mark is removed; color alone now conveys status (the instrument's own icon fills most of the circle instead, matching web's `InstrumentChip.tsx` proportions — a 24pt icon in a 34pt/56pt chip, ≈70%). Because color is now the *only* cue, `inconsistentFullCombo` can no longer share red with `noScore`: it gets its own `BrandTokens.statusAmber`/`statusAmberStroke`, a second, additive native safety deviation from the web (which paints it gold). The combined-row spoken announcement (unchanged) remains the accessible source of truth for status text.
- Web layout: 390px phone wraps nine chips 5+4; 820px tablet shows one row.
- Tokens: each status fill/stroke ≥3:1 against the card (`python3 -m tools.contrast_gate`); no glyph-on-fill ratio applies now that no glyph renders. Not rendered-screenshot proof.
