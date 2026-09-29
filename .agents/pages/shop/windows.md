# Item Shop — Windows notes

> **What:** the Windows Item Shop page: navigation, layouts per window size, states and decisions. **Read when:** changing `windows/Festival.App/Pages/ShopPage*`, `ShopViewModel` or `FestivalSession.Shop.cs`. Behavior: [spec.md](spec.md); offers/badges: [shop-offers/windows.md](../../controls/shop-offers/windows.md).

## Implemented

- Navigation: an **Item Shop** pane item (`fst.nav.shop`, `AppSection.Shop`, own frame stack) after Leaderboards/Rivals/Statistics, as in the web desktop sidebar. Removed from the pane while Hide Item Shop is on (the shell returns to Songs if it was showing); a `/shop` deep link while hidden shows "Item Shop Is Hidden".
- `GET /api/shop` once per publication through `FestivalSession.LoadShopAsync` (shared with Songs and Song Detail); the catalogue loads best-effort for in-app links.
- Offers in title order. Grid tiles follow the web `ShopCard`: square full-bleed art, bottom scrim with title and artist, a **Leaving Tomorrow** pill top-right, and a gold (New) / red (Leaving) pulse ring (`ShopPulseRing`, the Songs rows' 2 s clock); list rows keep the New / Leaving badges. Highlighting off removes pills, badges and pulses but keeps the links.
- The tile (`fst.shop.song.<id>`) opens Song Detail for catalogue songs (the official link otherwise); purchase is the tile's context menu item **Open in Item Shop** (`fst.shop.external.<id>`; right-click, Shift+F10 or press-and-hold), so tiles look like the web's `ShopCard` with no extra button (operator batch 6.9). List rows: row click → Song Detail, cart button (`fst.shop.external.<id>`) → official link.
- Reveal (operator batch 6.41/6.10): the visible layout waits behind a ring until the first 15 offers' art has decoded (≤ 900 ms), then fades its realized tiles/rows in with the shared stagger (`FadeIn.StaggerRealized`, repeater overload). A List/Grid switch scrolls to the top and replays this for the new layout, like the web's view toggle.
- Art: a recycled tile only takes the art of the load it still owns, and the shared byte cache forgets a download once it finishes even when every waiter had cancelled (a failed fetch used to stay "in flight" and replay its failure for the rest of the session: "art not loading", 6.9). A failed catalogue read keeps the offers with a "Song details unavailable" warning (`fst.shop.song-details-error`).
- States: loading, genuine empty card (`fst.shop.empty`), service status with Retry (`fst.shop.error`), hidden.

## Layouts

| Window | Layout |
|---|---|
| Compact (page < 640 epx) | Album-art grid forced (2 per row, as in the installed PWA; gap 7); toggle hidden |
| Medium / wide | Grid or list; **List View / Grid View** toggle (`fst.shop.view-toggle`) persisted in `AppSettings.ShopViewMode` |

Grid geometry (`Domain/ShopGridMetrics`, web `ShopPage.tsx`): 2 columns below 600 epx, 3 from 600, 4 from 860, 5 from 1100; 10 epx gaps; the grid is at most 1040 epx wide (web `min(window, 1080) - 40`), left-aligned, so wide windows keep ~200 epx tiles; tiles get explicit square sizes from the scroller's width (a `UniformGridLayout` Fill stretch rounded an exact two-column fit down to one column at 150%). Tile text follows the web card: 16 epx scrim padding, 16 epx semibold title, artist below.

## Native decisions

| Web | Windows | Why |
|---|---|---|
| Shop in hamburger/sidebar | Pane item | Windows NavigationView is the app's sidebar |
| WebSocket rotation updates | Re-read on publication change | Online-only reads; no socket client yet |

## Open

Rotation push updates; Quick Links. UIA: `songs_journey.py --only shop,shop-compact` covers grid, context-menu link, list toggle and Song Detail (never opens the real link).
