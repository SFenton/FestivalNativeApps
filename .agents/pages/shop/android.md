# Item Shop — Android notes

> **What:** the Android Item Shop page: navigation, layouts per window size, states and decisions. **Read when:** changing `ui/shop/`, `presentation/shop/` or `data/shop/`. Behavior: [spec.md](spec.md); offers/badges: [shop-offers/android.md](../../controls/shop-offers/android.md).

## Implemented

- Reached from the drawer (`fst.nav.drawer.shop` → `ShopRoute`, pushed on the current tab).
- `GET /api/shop` through `container.shop` (`ShopStore`): loaded once on first use (Shop page, Songs or Song Detail) and re-read when a newer publication is observed. The catalogue loads best-effort for in-app Details links.
- Title-ordered offers with **New** (gold on dark) / **Leaving Tomorrow** (white on red) text badges and matching 2 dp card borders; highlighting off removes badges and borders but keeps the links.
- Grid cards are the web `ShopCard` (6.9): square artwork filling the card, title/artist on a bottom scrim, a **Leaving Tomorrow** pill top-right, red/gold outline pulse. Tap opens the official link (`LocalUriHandler`, validated `https://www.fortnite.com/item-shop/jam-tracks/…` only; the song when there is none); **Song Details** is a long press and a TalkBack custom action. List rows open Details when matched (else the official link) with a trailing cart + chevron.
- List rows are the Songs page's shared `SongRowCard` (`ui/songs/SongRow.kt`, issue #18): the same glass card, 48 dp art, marquee title/subtitle and pulse outline as Songs rows. `ShopListRow` only fills its slots: the New / Leaving Tomorrow label under the subtitle (`fst.shop.badge.new|leaving.<id>`) and the cart + chevron button (`fst.shop.external.<id>`). It passes no merged description, so TalkBack reads the row's texts and the badge tags stay in the semantics tree. Do not reintroduce a page-local row: Songs and Shop must look the same.
- Switching List ↔ Grid rebuilds the new layout from the top with the fade/stagger again (`key(mode)` + `rememberViewSwitch`, web `useViewTransition`, 6.10).
- States: loading, empty (`FestivalEmptyState` "No Songs in the Item Shop", vertically centred, `fst.shop.empty`, 6.33), service status with Retry (`fst.shop.error`), "Song details unavailable" + Retry (`fst.shop.song-details-error`), hidden (`fst.shop.hidden`).

## Layouts

| Window | Layout |
|---|---|
| Compact (< 600 dp: phone, folded book/passport, tri-fold one panel) | List forced; toggle hidden |
| Medium / expanded (unfolded, tablet, resizable desktop) | Grid with the web's column counts (`shopGridColumns`: 3 from 600, 4 from 860, 5 from 1100 dp content) or list; **Grid View / List View** toggle (`fst.shop.view-toggle`) persisted in `fst.shop.viewMode` |

## Open

The drawer still lists Item Shop while Hide Item Shop is on (shell-owned `ShellChrome.kt`); rotation push updates; Quick Links; device journey for the toggle (never open the real link in automation).
