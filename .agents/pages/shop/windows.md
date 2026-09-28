# Item Shop — Windows notes

> **What:** the Windows Item Shop page: navigation, layouts per window size, states and decisions. **Read when:** changing `windows/Festival.App/Pages/ShopPage*`, `ShopViewModel` or `FestivalSession.Shop.cs`. Behavior: [spec.md](spec.md); offers/badges: [shop-offers/windows.md](../../controls/shop-offers/windows.md).

## Implemented

- Navigation: an **Item Shop** pane item (`fst.nav.shop`, `AppSection.Shop`, own frame stack) after Leaderboards/Rivals/Statistics, as in the web desktop sidebar. Removed from the pane while Hide Item Shop is on (the shell returns to Songs if it was showing); a `/shop` deep link while hidden shows "Item Shop Is Hidden".
- `GET /api/shop` once per publication through `FestivalSession.LoadShopAsync` (shared with Songs and Song Detail); the catalogue loads best-effort for in-app links.
- Offers in title order with New (gold on dark) / Leaving Tomorrow (white on red) badges and matching card borders; highlighting off removes badges and borders but keeps the links.
- Each offer opens the official link; matched catalogue songs also get **View Song Details** (grid) or row click (list). A failed catalogue read keeps the offers with a "Song details unavailable" warning (`fst.shop.song-details-error`).
- States: loading, genuine empty card (`fst.shop.empty`), service status with Retry (`fst.shop.error`), hidden.

## Layouts

| Window | Layout |
|---|---|
| Compact (page < 640 epx) | List forced; toggle hidden; badge under the title, 44 px official-link button |
| Medium / wide | Artwork grid (`UniformGridLayout`, min 200 epx, square art with scrim) or list; **List View / Grid View** toggle (`fst.shop.view-toggle`) persisted in `AppSettings.ShopViewMode` |

## Native decisions

| Web | Windows | Why |
|---|---|---|
| Shop in hamburger/sidebar | Pane item | Windows NavigationView is the app's sidebar |
| WebSocket rotation updates | Re-read on publication change | Online-only reads; no socket client yet |

## Open

Rotation push updates; Quick Links; UIA journey for grid/list toggle and links (never open the real link in automation).
