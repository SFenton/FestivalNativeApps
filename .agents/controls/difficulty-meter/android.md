# Difficulty meter — Android notes

> **What:** Compose implementation, validation and evidence. **Read when:** changing the meter or its hosts on Android. Spec: [spec.md](spec.md).

## Implementation

- `ui/design/DesignPrimitives.kt` `DifficultyMeter` draws the seven 62×20 dp parallelograms on a `Canvas` from `core/format` `DifficultyMeterSpec` (vertices, raw/display mapping and the accessible label are unit-tested). It is one TalkBack element (`contentDescription` "Difficulty N of 7", `Role.Image`; ImageView class on device), not focusable or clickable. Non-finite values render readable "Difficulty unavailable" text (`fst.songs.difficulty-unavailable`).
- Hosts: Song Detail Intensity card (`fst.song-detail.intensity.<wireId>`: one cleared stop "Lead, Difficulty 4 of 7"; icon + meter below 480 dp, icon + label + meter wider; the label keeps an 8 dp gap before the meter and wraps to two lines, unlimited at large text, instead of truncating), Song row metadata, and the Songs filter Song Intensity bucket switches (row visual's semantics cleared so the switch reads "Intensity N of 7, On" once).

## Validation (issue #123, 2026-10-03, live public service)

| Configuration | Result |
|---|---|
| FST_Phone portrait, landscape; font 1.0 and 2.0 | Levels 1–7 render (Notorious Thugs Bass = 1, Go Go Power Rangers Lead = 7). Landscape font 2.0: "Pro Drums + Cymbals" touched the meter → fixed with an 8 dp label end gap; now wraps |
| FST_Phone light theme | Identical: the app theme is dark-only by design |
| FST_Tablet portrait, landscape (+ font 2.0) | Labelled two-column card; long label wraps at 2.0 |
| FST_Resizable phone / foldable / tablet / desktop | Compact icon + meter cells, then labelled cells at medium/expanded widths |
| FST_Book_Fold folded / half / unfolded (+ font 2.0) | Compact cells folded; half-open splits the card across the hinge; labelled unfolded |
| FST_Passport_Fold folded / half / unfolded (+ font 2.0) | Same as Book Fold |
| FST_TriFold folded / partial / unfolded (+ font 2.0) | Compact folded; partial (≈600 dp pane) first truncated "Pro Drums + Cymb…" with the 12 dp gap, so the label now wraps to two lines; labelled unfolded |
| `invalid` | Not reachable with live data (`chartedValue` drops non-finite values); covered by tests only |

Accessibility: no animation (reduced motion n/a); the meter is not interactive (no touch target); bars #FFFFFF vs #666666 ≈ 5.7:1, unfilled vs the card ≈ 3.3:1, and the level is always in the spoken label. Two shared findings fixed alongside (see [android-accessibility.md](../../testing/android-accessibility.md)): duplicate filter switch speech and a 32 dp sheet drag handle.

## Material 3 deviations (deliberate)

Reviewed against the `material-3` skill (Compose). The spec mandates brand #FFFFFF/#666666 instead of colour-scheme roles and forbids substituting a platform `LinearProgressIndicator`; the meter therefore exposes `Role.Image` plus the level in its description rather than progress semantics.

## Tests

- `DifficultyMeterUiTest` (Robolectric): every level's role and label, bar pixels in brand colours, display clamp, NaN/Inf → unavailable, font 2.0 geometry and unclipped wrap, filter switches speak once with a ≥ 48 dp drag handle, Song Detail labels keep ≥ 8 dp before the meter at 200% in landscape.
- `DifficultyMeterDeviceTest` (connected; FST_Phone, FST_Tablet, FST_Book_Fold, FST_Passport_Fold folded, FST_TriFold unfolded, FST_Resizable tablet): reading order "Difficulty 1…7 of 7" / "Difficulty unavailable" as ImageView with ATF, font scale 2, and the filter journey.