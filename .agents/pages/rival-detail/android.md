# Rival Detail — Android notes

> **What:** Android state of `/rivals/:rivalId`. **Read when:** changing `RivalDetailScreen` / `RivalDetailViewModel` in `android/`. Full Rivals notes: [../rivals/android.md](../rivals/android.md).

- Resolves the route's scope with `RivalScopes.resolveDetail` (leaderboard, one or more merged song scopes, Settings fallback); `allowLiveFallback` only from Find Rival.
- Header "You vs. Name" + web `rivals.detail.summary`; the web's six categories (`RivalCategorization`, same keys, split rules and descriptions) as cards of five songs with sentiment-tinted headings, View All → Rivalry forwarding scope and live-fallback flag.
- Toolbar: Quick Links (shared `QuickLinksAction`; web `rival-category:<key>` items with the category titles, `RivalQuickLinks.rivalDetail`; the web shows them only on mobile chrome, Android at every size like Song Detail; the shared rule needs 2+ categories) and View Profile (`PlayerRoute`). Song rows open Song Detail; the catalogue is read best-effort for year and artwork. No song data → "No song data for this rival."
- Freeze (#95): sends the web's detail query; a cold-key 503 rebuilds the comparison from `/rivals/all` song samples before falling back to the retry state.
- Rule (#321): each category card opens Rivalry from the shared title-row "View All ›" link (`SeeAllButton`, spoken "View All: <category>"), like the web's card-header link; there is no in-card bottom row, so no purple [view-all-cta](../../patterns/view-all-cta.md) here. The app never says "See All" (`section-headers/android-view-all-copy` guard).

## Validation (#109)

| Configuration | Layout (live service) |
|---|---|
| `FST_Phone` portrait / landscape | 1 column / 2 columns; bottom bar + floating toolbar |
| `FST_Tablet` portrait / landscape | Rail + 1 column / drawer + 2 columns |
| `FST_Resizable` phone / foldable / tablet / desktop | 1 / 1 / 2 / 3 columns (`AdaptiveCardGrid`: ≥360 dp columns, max 3) |
| `FST_Book_Fold`, `FST_Passport_Fold` | Folded = phone; unfolded 1 column; half-open 2 columns split at the hinge, no card spans it |
| `FST_TriFold` | Folded = phone; partial 1 column; unfolded 2 columns |
| Font scale 2.0 (phone, tablet, folds) | Text wraps, nothing clipped; long rival names wrap inside the compare column |

- Theme: Android is dark-only by design ([../../design/android.md](../../design/android.md)); the system light theme does not change this page (deliberate deviation from Material 3 dynamic light/dark).
- Material 3 alignment (`material-3` skill, Compose): multi-pane from medium width (≥600 dp), hinge-aware panes, 48 dp touch targets on rows, View All and toolbar actions.
- TalkBack: song cards speak full unsigned gaps with singular nouns (`RivalHeadToHead.leaderPhrase` / `spokenScoreDiff`, e.g. "Rival leads by 1 rank, your score is 94 points lower"; a tie reads "tied, same score"), never "+1"/"−94". `RivalSectionHeader` makes title + description a traversal group so TalkBack reads heading → description → View All (a vertically centred View All otherwise sorted between them).
- Tests: Robolectric `RivalsUiTest` (loaded, no songs, no player, failed → retry, scrape freeze countdown, Quick Links, expanded columns), `RivalsAllDetailTest` (cold-key `/rivals/all` fallback), `RivalRowUiTest` (row labels, header order), `RivalsCoreTest`; connected `RivalsDeviceJourneyTest`, `PlayerAccessibilityJourneyTest`.
