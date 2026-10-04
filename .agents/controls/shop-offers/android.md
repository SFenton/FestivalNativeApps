# Shop offers — Android notes

> **What:** how Android validates Shop offers and applies badges/borders across Shop, Songs and Song Detail. **Read when:** touching `core/shop/`, `presentation/shop/ShopStore.kt` or Shop accents. Behavior: [spec.md](spec.md).

- `ShopResponse.validate` rejects count mismatches, duplicate (case-insensitive) or `/`-containing IDs, empty titles/artists and any URL that isn't `https://www.fortnite.com/item-shop/jam-tracks/<slug>` without credentials, port, query or fragment. Bodies over 4 MB are rejected.
- `ShopPresentationPolicy.highlight`: Leaving Tomorrow, then New; none when Shop is hidden, highlighting is disabled or there's no offer.
- `SongRelatedPublicationPolicy.matches(catalogue, shop, current)` gates Songs sort/filter/accents and Song Detail's badge/link: a feed from another observed publication pauses Shop choices with a notice and never decorates older rows.
- Songs rows: 2 dp red (Leaving) / gold (New) border plus a circular badge (clock / sparkle); the row announcement adds "Item Shop: …". Shop page and Detail use text badges.
- One process-wide `ShopStore` (AppContainer `shop`) shared by all three surfaces; online-only, in-process.

## Validation (issue #131, 2026-10-04)

Emulator API 37, debug build, live public service (keyless; no selected-profile headers). Dark scheme only by repo rule; the system light theme was checked and the app stays dark.

| Configuration | Result |
|---|---|
| FST_Phone portrait, font 1.0 and 2.0; system light | OK: list forced, toggle hidden. At 2.0, titles and subtitles wrap without clipping. |
| FST_Phone landscape, font 1.0 and 2.0 | OK: 3-column grid. At 2.0 the card titles wrap. |
| FST_Tablet portrait (3 columns) and landscape (4 columns), grid and list, font 1.0 and 2.0 | OK |
| FST_Resizable phone / foldable / tablet / desktop | OK: list, 3, 4 and 5 columns |
| FST_Book_Fold folded / unfolded | OK: list; 4-column grid or full-width list |
| FST_Book_Fold half-open (separating vertical hinge) | **Fixed**: the 3-column grid's middle cards and every full-width list row straddled the fold. Cards now go 2 + 2 around it, and list rows flow leading pane → trailing pane. At font 2.0 the list is full width (no split, `rememberSingleColumn`, as on every page). |
| FST_Passport_Fold folded / half / unfolded | OK: list; 4 columns, with the half-open hinge falling in a gutter (non-separating); 3 columns |
| FST_TriFold folded / partial / unfolded | OK: list; 2 columns, one on each side of the hinge; 3 columns or list |

- Accessibility:
  - A real TalkBack walk on FST_Phone reads Search, then Choose profile, then each offer: "Title. Artist · year" followed by "Open <title> in the Fortnite Item Shop. Button". Initial focus is TalkBack's heuristic, as on Songs.
  - ATF found no issues: connected `SongsAccessibilityJourneyTest.itemShop` on FST_Phone and on FST_Book_Fold `--posture half`, with reading order, grid ⇄ list, the filter sheet and `assertNothingStraddles` on every offer and link.
  - **Fixed**: the list row's cart button was 40 dp wide. It is now at least 48 × 48 dp (`sizeIn`), asserted in `populatedListIsTitleOrderedWithBadgesAndLargeTargets`.
  - Reduced motion: device runs use animator scale 0, and the pulse and stagger respect Reduce Motion.
- Material 3 deviations, deliberate:
  - Dark scheme only (brand).
  - Grid cards are the web `ShopCard` (artwork, bottom scrim, pill badge) rather than an M3 `Card`, for parity.
  - The red/gold pulse outline follows the web, not M3 state layers.
- States → tests. Robolectric `ShopOffersStatesUiTest`, unless noted:

| States | Tests |
|---|---|
| `hidden` | `hiddenShowsTheNoticeWithoutPageTools` |
| `loading` | `loadingShowsTheSpinnerUntilTheFeedArrives` |
| `empty` | `emptyFeedIsTheEmptyStateNotAnError` |
| `failed` | `failureOffersRetryThatRecovers` |
| `offline` | `offlineIsAnExplicitOfflineState` |
| `unverified` | `untrustedShopLinkRejectsTheFeed` |
| `populated`, `new`, `leaving`, `list` | `populatedListIsTitleOrderedWithBadgesAndLargeTargets` |
| `grid` | `gridCardsAreSquareAndListToggleKeepsTheOffers` |
| `official-link` | `officialLinkOpensTheFortniteItemShop` |
| `song-detail` | `songDetailShowsTheShopActionWithItsStatus`, `songDetailShowsAnExplicitShopError` |
| `highlight-disabled` | `highlightsOffHideBadgesButKeepTheLink` |
| `filtered` | `filterNarrowsTheOffersLive` |
| `filter-no-match` | `filterWithNoMatchIsDistinctFromEmpty` |
| half-open hinge | `halfOpenBookFoldKeepsGridCardsAndListRowsOffTheHinge`, `halfOpenBookFoldKeepsCentredStatesOnTheLeadingPane`, `ShopColumnPolicyTest`, plus connected `itemShop` on `--posture half` |
