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
| Medium / expanded (unfolded, tablet, resizable desktop) | Grid with the web's column counts (`ShopColumnPolicy.gridColumns`: 3 from 600, 4 from 860, 5 from 1100 dp content) or list; **Grid View / List View** toggle (`fst.shop.view-toggle`) persisted in `fst.shop.viewMode` |
| Half-open book / passport (separating vertical hinge, issue #131) | `rememberHingeSplit` + `ShopColumnPolicy.resolve`: one `LazyVerticalGrid` whose custom `GridCells`/`Arrangement` (`ShopCells`) leaves a gap of max(hinge, gutter) on the fold. Each pane gets its own column count (grid: `gridColumns(pane)`, uniform card width = the narrower pane's; list: one row per pane, flowing leading → trailing in title order). Header, empty, no-match, loading, failed and hidden states stay in the start pane (`fst.shop.start-pane`). Under TalkBack or large text (`rememberSingleColumn`) there is no split, as on every page: one full-width column. |

## Open

The drawer still lists Item Shop while Hide Item Shop is on (shell-owned `ShellChrome.kt`); rotation push updates; Quick Links; device journey for the toggle (never open the real link in automation).
