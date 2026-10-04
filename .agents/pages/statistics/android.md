# Statistics — Android notes

> **What:** how the Android Statistics tab renders the selected player's profile. **Read when:** changing `StatisticsScreen` or the follow-selection mode of `PlayerProfileViewModel`. Shared body: [player-profile/android.md](../player-profile/android.md).

- `StatisticsTab` (tab root: hamburger and avatar) and `StatisticsRoute` (pushed) render `PlayerProfileContent` with `PlayerProfileViewModel(accountId = null)`, always showing the selected player with Deselect (web `App.tsx` routes `/statistics` to `PlayerPage`).
- It mirrors `SelectedProfileStore` instead of reading again; Retry calls `store.retry()`.
- Per-entity reset: a switch re-targets the page and clears the rank and history cards; a deselect removes the tab (`FestivalTabPolicy`) and the page shows `fst.player.no-profile` until the shell moves to Songs. The tab does not restore nested history (`resetsPathOnLeave`).
- Root tag `fst.statistics`; everything inside uses `fst.player.*`.

## Validation (issue #111, 2026-10-03)

Live public service (keyless; `/api/player/{id}`, rankings, rank history and player bands reads only), selected player SFentonX via `FST_DEBUG_PROFILE`, debug APK driven with `tools/android/fst_android.py device drive`. Each configuration checked load, Overview, Lead/instrument cards, Quick Links (sheet < 600 dp, top-bar menu otherwise) to Lead, Top Songs, Bands and back to Global, and that no card straddles a separating hinge.

| Configuration | Result |
|---|---|
| FST_Phone portrait, 100% / 200% | OK. One column; tiles 2-up at 100%, wrap without clipping at 200%; nav bar icon-only at 200%; sheet jumps land 32 dp below the bar. Found and fixed: first Top Songs/Bands jump landed low (landing hold) and a font-scale change mid-load left the page spinning (`SelectedProfileStore` resume) |
| FST_Phone landscape (`wm user-rotation lock 1`; the drive's `rotate:` step is a no-op on this AVD), 100% / 200% | OK. 923 dp: Quick Links move to the top-bar menu; Overview 4 tiles across at 100%, 2 at 200% |
| FST_Tablet landscape / portrait, 100% / 200% | OK. Drawer and two lanes (landscape), rail and one column (portrait); rail icon-only at 200%; menu items wrap at 200% |
| FST_Resizable phone / foldable / tablet / desktop | OK. Bar → rail → drawer; 1 → 2 → 3 lanes; 200% checked at foldable and desktop |
| FST_Book_Fold folded / unfolded / half-open, 100% / 200% | OK after fix. Half-open splits at the hinge (no straddling card). Found and fixed: unfolded → Top Songs → half-open → Global left a lane gap and hid Lead (`rememberProfileGridState`) |
| FST_Passport_Fold folded / unfolded, 100% / 200% | OK. Unfolded: rail, two lanes, menu; folded: bar, sheet; one column folded at 200% |
| FST_TriFold folded / partial / unfolded, 100% / 200% | OK. All postures are flat (not separating), so width rules apply: two lanes unfolded, one column partial and folded, one column at 200% |
| Light theme (`dark:off`) | Stays dark by design (the product uses one dark scheme, as on the web) |
| Reduced motion (animator, transition and window scales 0) | OK. Content appears without fades and Quick Links jumps land instantly (`device.py` also defaults to scale 0) |
| Accessibility | TalkBack walk on FST_Phone in visual order with headings, roles and disabled states; ATF `PlayerAccessibilityJourneyTest#statisticsProfile` and `ProfileDeviceJourneyTest` pass on FST_Phone, and on FST_Book_Fold half-open ([android-accessibility](../../testing/android-accessibility.md)) |
| Tests | Robolectric: 982 tests pass; logic coverage 98.0%, UI 94.1% (gates 95/90). New: `SelectedProfileStoreTest.readInterruptedByARecreatedOwnerResumesInTheNextOwner`, `QuickLinksControllerUiTest` landing hold and staggered-lane cases (each mutation-checked) |

Deliberate deviations from the `material-3` skill: one dark scheme (no light/dynamic colour); navigation goes icon-only at ≥ 130% font instead of truncating labels; chart axis ticks keep their 100% size (values are listed under each chart); one column under TalkBack or large text in place of multi-pane reading; small top app bar titles ellipsize at 200% (the page heading repeats them); desktop width uses up to three 340 dp lanes rather than a capped body width.
