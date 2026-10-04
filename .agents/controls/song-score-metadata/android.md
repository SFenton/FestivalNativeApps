# Song score metadata — Android notes

> **What:** Android rendering of the icons-off / single-chart selected-player metadata pills, validation and evidence. **Read when:** changing `SongMetadataPolicy`, `SongRowProjector` or `MetadataPill`. Behavior: [spec.md](spec.md).

## Implementation

- Chart: the filtered chart, else the first **visible** chart (`AppSettings.orderedVisibleInstruments`); a non-Lead chart shows and speaks "{chart} chart".
- Order: `songRowVisualOrder` when Enable Visual Order is on, else the web default; visibility from `visibleMetadata`. With Percentage hidden an FC still yields an **FC** pill.
- Pills: bold grouped score in tabular figures (`tnum`, end-aligned); accuracy tinted red→green at 25% (FC: gold outline, "98.7% FC"); percentile Top 1% gold fill, Top 5% gold outline, else neutral; 1–5 white stars in web `MiniStars` circles (service 6 = five gold with the gold ring; [star rating](../star-rating/android.md)); `S15` inverted for the current catalogue season; intensity meter (raw + 1); E/M/H/X difficulty (dark glyphs on Easy/Hard).
- Last Played follows the web: it appears only under the Last Played sort, as the **primary** value. The pill text is the date ("1 Sep 2026"), and the row speaks "Last played 1 Sep 2026". With icons on, the trailing entry is the played chart's icon plus the date. The spec's "toggle-controlled date under Title" native deviation is superseded on Android now that the sort ships.
- The first pill (or Last Played entry, or the Max Distance "score / max" dual) sits top-trailing beside the title in a box capped at `PRIMARY_MAX_FRACTION` (50%) of the header width; text wraps inside it rather than squeezing the title. The rest wrap right-aligned in a `FlowRow` (`fst.songs.metadata.<songId>`, per-field `fst.songs.metadata.<field>.<songId>`). Pill text may wrap (no `maxLines`), so 2.0 text grows rather than clips.
- Zero score, missing chart, loading/202/failed/paused scores and Filter Invalid Scores show explicit text instead (`fst.songs.score-state.<songId>`). Filter Invalid Scores adds the invalid-score icon as a second 48 dp TalkBack stop; a corrupt saved filter shows the paused state until Reset.
- The whole row is one TalkBack stop (merged `contentDescription` in field order); the Shop badge is spoken after the metadata.

## Validation (issue #135, 2026-10-06, live public service)

Live: profile `SFentonX` (debug profile launch, no selected-profile headers), Show Instrument Icons off unless noted. All configurations show the Score primary top-trailing and the pills right-aligned: 100% FC (gold outline), Top 1% (gold fill) / Top 4% (gold outline), five gold Mini stars, S15 inverted / older seasons muted, the intensity meter, the X difficulty pill and the Shop badge.

| Configuration | Result |
|---|---|
| FST_Phone portrait, font 1.0 | Pills wrap 2+4 under the score; titles marquee/ellipsize per the row spec |
| FST_Phone portrait, font 2.0 | Rows grow; pills wrap over two lines without clipping. **Found:** under the Last Played sort the wrapped "14 Aug 2024" entry took 60% of the header and broke the title one word per line; fixed by the 50% cap (title now wraps only at word breaks) |
| FST_Phone landscape, font 1.0 / 2.0 | 1.0: list-detail, pills on two lines in the list pane. 2.0: single pane, pills on one line |
| FST_Phone light theme | Identical: the app theme is dark-only by design |
| FST_Tablet landscape / portrait, font 1.0 / 2.0 | Landscape permanent drawer and portrait rail: pills fit one line beside the score at 1.0 and 2.0 |
| FST_Resizable compact / medium / expanded / desktop | Compact at 1.0/2.0 matches the phone. Medium (800 dp) rail and expanded at 2.0: one line. Desktop list-detail: the narrow list pane wraps the meter and difficulty to a second right-aligned line |
| FST_Book_Fold folded / unfolded | Unfolded (rail) at 1.0 and 2.0: one line per row. Folded at 2.0: pills wrap 3+3 without clipping. Unfold→fold (recorded) moves from list-detail to the single pane and re-wraps the pills to the outer width |
| FST_Passport_Fold folded / unfolded, font 1.0 / 2.0 | Folded at 2.0: phone-like wrap, no clipping. Unfolded at 2.0: rail, one line per row |
| FST_TriFold folded / partial / unfolded | Unfolded at 1.0 and 2.0 and partial (two panels) at 1.0: one line. Folded (one panel): titles ellipsize and the pills wrap 2+3 under the score. A drive that applies the folded posture before the first tap loses the Settings node during the posture switch (tooling; start unfolded) |
| Unreachable live states | `anonymous`, `loading`, `syncing`, `failed`, `invalid-filter-paused`, `missing-accuracy`, `fc-only`, `non-lead-chart-named` with a Lead-first profile and `band-blocked` aren't reproducible against the live service with SFentonX (or at all: Android Songs has no band identity, so `band-blocked` can't occur). Covered by Robolectric and device tests |

Accessibility: each row is one TalkBack stop that reads title, artist line, then the fields in visual order ("Score 1,234,567, Accuracy 98.7%, Top 1%, 5 gold stars, Current season 15, Song intensity 4 of 7, Easy difficulty"); the Filter Invalid Scores icon is a separate 48 dp stop. ATF passes on device. Pills are non-interactive (no touch target needed); the row is ≥ 48 dp. Pill tokens meet 4.5:1 text / 3:1 edges (Easy #2ECC71 and Hard #2D82E6 use dark #0B1220 glyphs; Medium #C62828 and Expert #7C3AED white). No motion: reduced motion n/a (the meter and pills don't animate; device tests run at animator scale 0). Star images keep icon size at 2.0, and the star count is always spoken.

## Fixed in #135

- At font 2.0 a wide primary value (the Last Played date, the "score / max" dual) starved the weighted title column. The primary is now capped at 50% of the header width and wraps inside its box.
- The Last Played pill repeated "Last played" visually; it now shows the date and speaks the prefix.
- The dual "score / max" value is one text (tagged `fst.songs.max-score.<songId>`) so it wraps as a unit; the score uses tabular figures.

## Material 3 deviations (deliberate)

Reviewed against the `material-3` skill (Compose): "verify contrast: UI components often need 3:1 for large text/borders and 4.5:1 for normal text (WCAG 2.x)"; "TalkBack/semantics (Compose), focus order, touch targets (~48dp)"; component catalog "Minimum touch target 48x48dp". The pills are non-interactive web-parity badges (6 dp corners, brand gold and difficulty colours), not M3 `AssistChip`/`FilterChip`: chips imply an action, and the spec makes the whole row the single navigation action. Colours are brand tokens rather than colour-scheme roles for parity with the web, with contrast gated in tests.

## Tests

- `SongsCoreTest` (JVM): policy, order, chart choice, Last Played text and announcement.
- `SongScoreMetadataUiTest` (Robolectric, 24 tests): every reachable state — `anonymous`, `loading`/`syncing`/`failed`/paused, `no-score`, `score-primary`, `score-hidden-accuracy-primary`, `fc`, `fc-only`, `graded-accuracy`, `missing-accuracy`, `top-one`, `top-five`, `ordinary-percentile`, `five-gold-stars`, `ax-star-count`, `current-season`, `old-season`, `catalogue-intensity`, `game-difficulty`, `last-played-native-deviation`, `non-lead-chart-named`, `ax5-wrapped-date-trailing`, `filtered-chart`, `invalid-filter-paused`, `shop-badge`, `narrow`, `regular`, `accessibility-text`, `sidebar-transition` (pane width change) and `contrast` (token ratios). `largeTextPrimaryValuesLeaveTheTitleRoom` guards the 50% cap (fails at 0.6).
- `SongScoreMetadataDeviceTest` (connected, 4 tests): reading order with ATF for the row states and the invalid-score second stop; 1.0/2.0 layout (pills inside the card, wrapped pills right-aligned, title column at least the primary's width) for Score, Last Played, dual and icons-on Last Played rows; pane-width re-wrap. Passed 4/4 on FST_Phone and FST_Book_Fold unfolded.
