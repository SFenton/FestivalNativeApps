# Item Shop — Android notes

> **What:** the Android Item Shop page: navigation, layouts per window size, states and decisions. **Read when:** changing `ui/shop/`, `presentation/shop/` or `data/shop/`. Behavior: [spec.md](spec.md); offers/badges: [shop-offers/android.md](../../controls/shop-offers/android.md).

## Implemented

- Reached from the drawer (`fst.nav.drawer.shop` → `ShopRoute`, pushed on the current tab).
- `GET /api/shop` through `container.shop` (`ShopStore`): loaded once on first use (Shop page, Songs or Song Detail) and re-read when a newer publication is observed. The catalogue loads best-effort for in-app Details links.
- Title-ordered offers with **New** (gold on dark) / **Leaving Tomorrow** (white on red) text badges and matching 2 dp card borders; highlighting off removes badges and borders but keeps the links.
- Grid cards are the web `ShopCard` (6.9): square artwork filling the card, title/artist on a bottom scrim, a **Leaving Tomorrow** pill top-right, red/gold outline pulse. Tap opens the official link (`LocalUriHandler`, validated `https://www.fortnite.com/item-shop/jam-tracks/…` only; the song when there is none); **Song Details** is a long press and a TalkBack custom action. List rows open Details when matched (else the official link) with a trailing cart + chevron.
- List rows are the Songs page's shared `SongRowCard` (`ui/songs/SongRow.kt`, issue #18): the same glass card, 48 dp art, marquee title/subtitle and pulse outline as Songs rows. `ShopListRow` only fills its slots: the New / Leaving Tomorrow label under the subtitle (`fst.shop.badge.new|leaving.<id>`) and the cart + chevron button (`fst.shop.external.<id>`). It passes no merged description, so TalkBack reads the row's texts and the badge tags stay in the semantics tree. Do not reintroduce a page-local row: Songs and Shop must look the same.
- Switching List ↔ Grid rebuilds the new layout from the top with the fade/stagger again (`key(mode)` + `rememberViewSwitch`, web `useViewTransition`, 6.10).
- **Filters** (issue #19): a FilterList icon (`fst.shop.filter.open`, "Filter Item Shop", gold while a filter is on) on every width opens `ShopFilterSheet`, the Songs `LiveSheet` with Songs `ToggleRow` switches **New**, **Available**, **Leaving Tomorrow** (`fst.shop.filter.new|available|leaving`), Reset (`fst.shop.filter.reset`) and Done (`fst.shop.filter.done`). Native decisions: *Available* = offers that are neither New nor Leaving Tomorrow; switches combine as a union; all off (default, Reset) shows every offer; filters read the wire `isNew`/`leavingTomorrow` flags, so they work with highlighting off; changes apply live like Songs; state lives in `ShopViewModel` (back-stack entry, not persisted). A filter that hides every offer shows "No Matching Songs" + Reset Filters (`fst.shop.filter.empty`, `.empty-reset`), never the empty-Shop state.
- States: loading, empty (`FestivalEmptyState` "No Songs in the Item Shop", vertically centred, `fst.shop.empty`, 6.33), service status with Retry (`fst.shop.error`), "Song details unavailable" + Retry (`fst.shop.song-details-error`), hidden (`fst.shop.hidden`).

## Layouts

| Window | Layout |
|---|---|
| Compact (< 600 dp: phone, folded book/passport, tri-fold one panel) | List forced; toggle hidden |
| Medium / expanded (unfolded, tablet, resizable desktop) | Grid with the web's column counts (`shopGridColumns`: 3 from 600, 4 from 860, 5 from 1100 dp content) or list; **Grid View / List View** toggle (`fst.shop.view-toggle`) persisted in `fst.shop.viewMode` |

Grid and list are capped at 1040 dp and centred (`shopSideMargin`, issue #113). The cap matches the web (`min(window, 1080) - 40`) and Windows (`ShopGridMetrics.MaxContentWidth`), and follows M3 layout guidance: *"Constrain body content to a max width (typically 840–1040dp) and center it"*. The side padding is content padding, so the list still scrolls edge to edge. Columns follow the page width, so a 1920 dp desktop window shows five 200 dp tiles instead of 300 dp posters, and list rows stay readable instead of being about 1,500 dp wide. Pure test: `ShopLayoutTest`. UI test: `ShopUiTest.desktopWidthCentresAFiveColumnGridNoWiderThan1040dp`.

**Hinge split** (issue #113). A separating vertical hinge, such as a book or passport fold half-open, splits the grid at the fold (`ShopGridLayout.kt`: `shopGridSplit`, `ShopSplitCells`, `ShopSplitArrangement`). Before the fix, the middle column's cards straddled the fold. M3 says never to place interactive content across a hinge, and the Profile, Rivals and Suggestions grids already split. The panels share one square tile size (at least 120 dp). Each panel packs its tiles against the hinge, so the halves mirror, and the hinge (or the 10 dp gap, whichever is wider) becomes the gutter. Hinge bounds come from `currentWindowAdaptiveInfo().windowPosture.hingeList`, never from device names. A flat (non-separating) fold keeps the normal grid: M3 allows a scrolling feed across a flat fold.

**Card text at large font sizes** (issue #113). A grid card is a fixed square. At 2.0× a long title used to push the artist line out of the tile's bottom edge. `shopCardTextHeights` now caps the title at about two thirds of the scrim room and the artist at the rest, each at least one line, so both end in "…". TalkBack still reads the full title and artist from the card's description.

## Validation (issue #113, 2026-10-03, live public service)

Debug APK checked on each AVD with `device.py drive --route shop --extra FST_DEBUG_STILL_BACKGROUND=1`. Live data: 125 offers, 1 Leaving Tomorrow, 0 New. Screenshots stay outside git.

| Configuration | Finding |
|---|---|
| FST_Phone portrait/landscape, 1.0×/2.0× | Compact list (landscape is 923 dp: grid with 3 columns and a toggle). At 2.0× titles and artists wrap inside the row with no clipping, and the cart button stays a 48 dp touch target (40 dp IconButton container padded by `minimumInteractiveComponentSize`). At rest the floating Filter toolbar covers the lowest visible row's cart button. This is deliberate: the shell's shared M3 floating toolbar hides when you scroll (`FestivalApp` `toolbarScroll`), and the list reserves its height at the end. |
| Light vs dark system theme | Identical: the app is dark-only by design ([design/android.md](../../design/android.md)). |
| FST_Tablet landscape 1280 dp / portrait 800 dp | Drawer and 4 columns; rail and 3 columns. List/Grid toggle and filter sheet work. At 2.0× the grid scrims grow to four lines inside the tiles. |
| FST_Resizable phone / foldable (+rotated) / tablet / desktop | Compact list, medium rail and grid, then expanded. Desktop was full-width before the fix and is now a centred 1040 dp grid/list (fixed). |
| FST_Book_Fold folded / unfolded / half-open, 1.0×/2.0× | Folded (CLOSED) is the compact list; 2.0× wraps without clipping. Unfolded (OPENED, flat fold at x = 1038 px) is a 3-column grid with the rail. Half-open (HALF_OPENED, separating) used to put the middle column across the fold; it now shows 2 + 2 tiles that mirror around the fold (**fixed**). At 2.0× long titles and artists used to run off the tile; they now end in "…" (**fixed**). |
| FST_Passport_Fold folded / unfolded / half-open, 1.0×/2.0× | Folded is the compact list (2.0× wraps cleanly). Unfolded is 3 columns. Half-open shows 2 + 2 tiles split at the fold (x = 1104 px). |
| FST_TriFold folded / partial / unfolded, 1.0×/2.0× | Folded (720 px) is the compact list. Partial is 2 columns and unfolded is 4 columns with the rail. The emulator reports no `FoldingFeature` in any posture, so the grid never splits; the split code is driven only by WindowManager hinges. At 2.0× unfolded, the card-text caps keep the long artists inside the tile. |
| Connected tests | `device.py test SongsAccessibilityJourneyTest#itemShop` passes on FST_Phone and FST_Tablet: reading order, the toggled view, and the Accessibility Test Framework checks on touch-target size, labels and contrast. |
| TalkBack | Walk on FST_Phone (`talkback_walk.py --route shop`): Item Shop, Search, Choose profile, then each row ("Title. Artist · Year", the first one adding "In list. 126 items"), followed by "Open … in the Fortnite Item Shop. Button". Grid cards read "Title, Artist[, Leaving Tomorrow]. Opens the Fortnite Item Shop" with a **Song Details** custom action. Reduced motion: all drives ran with animator scale 0, and the pulse holds its colour (`rememberShopPulse`). |

Robolectric `ShopUiTest` covers loading, the compact list (badges, labelled 48 dp link, opening the official URL), highlighting off, the medium grid (description, custom action, card tap, Details), the desktop cap and 2.0× text in the list, grid and filter sheet. `ShopLayoutTest` covers the column counts, the side margin, the hinge split (book fold, wide hinge, tri-fold, no hinge), the split cells and arrangement (including the RTL mirror and fallbacks) and the card-text caps. `SongsUiTest` keeps the empty, failure, filter, no-match and hidden states.

## Open

The drawer still lists Item Shop while Hide Item Shop is on (shell-owned `ShellChrome.kt`); rotation push updates; Quick Links; device journey for the toggle (never open the real link in automation).
