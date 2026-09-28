# Item Shop — Android notes

> **What:** the Android Item Shop page: navigation, layouts per window size, states and decisions. **Read when:** changing `ui/shop/`, `presentation/shop/` or `data/shop/`. Behavior: [spec.md](spec.md); offers/badges: [shop-offers/android.md](../../controls/shop-offers/android.md).

## Implemented

- Reached from the drawer (`fst.nav.drawer.shop` → `ShopRoute`, pushed on the current tab).
- `GET /api/shop` through `container.shop` (`ShopStore`): loaded once on first use (Shop page, Songs or Song Detail) and re-read when a newer publication is observed. The catalogue loads best-effort for in-app Details links.
- Title-ordered offers with **New** (gold on dark) / **Leaving Tomorrow** (white on red) text badges and matching 2 dp card borders; highlighting off removes badges and borders but keeps the links.
- Grid card tap opens the official link (`LocalUriHandler`, validated `https://www.fortnite.com/item-shop/jam-tracks/…` only) with a separate **Song Details** action for catalogue songs; list rows open Details when matched (else the official link) with a trailing official-link button.
- States: loading, genuine empty card (`fst.shop.empty`), service status with Retry (`fst.shop.error`), "Song details unavailable" + Retry (`fst.shop.song-details-error`), hidden (`fst.shop.hidden`).

## Layouts

| Window | Layout |
|---|---|
| Compact (< 600 dp: phone, folded book/passport, tri-fold one panel) | List forced; toggle hidden |
| Medium / expanded (unfolded, tablet, resizable desktop) | `LazyVerticalGrid(Adaptive(180 dp))` or list; **Grid View / List View** toggle (`fst.shop.view-toggle`) persisted in `fst.shop.viewMode` |

## Open

The drawer still lists Item Shop while Hide Item Shop is on (shell-owned `ShellChrome.kt`); rotation push updates; Quick Links; device journey for the toggle (never open the real link in automation).
