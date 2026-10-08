# Item Shop (`/shop`) — spec

> **What:** platform-neutral web behavior of the Item Shop route: wire, navigation, states and cross-page effects. **Read when:** changing Shop on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md). Offer/badge control: [shop-offers](../../controls/shop-offers/spec.md).

Source: `FortniteFestivalWeb/src/pages/shop/ShopPage.tsx:41-190`, `src/pages/shop/components/ShopCard.tsx:18-109`, `src/contexts/ShopContext.tsx:30-129`, `src/hooks/data/useShopState.ts:1-61`, `src/components/shell/mobile/BottomNav.tsx:45-75`, `FSTService/Api/SongEndpoints.cs:244-255`, `FSTService/Api/ShopCacheService.cs:48-92`, `FSTService/Scraping/ShopUrlHelper.cs:14-34`.

## Wire

- Keyless, publication-aware `GET /api/shop` → `count`, enriched `songs`, `isNew`, `leavingTomorrow`, official `shopUrl`, optional update metadata. ETag/304 valid only within the current publication.
- Validate count and unique IDs, non-empty titles, and **HTTPS `www.fortnite.com/item-shop/jam-tracks/`** outbound links. Independent of profile search and rankings. Live read 2026-09-25: 133 items (1 New, 1 Leaving Tomorrow).

## Navigation

- The web reaches Shop from its wider nav / hamburger — **not** a fourth no-profile mobile tab.
- The web card opens the official Shop URL. A matched catalogue song may additionally get an in-app Song Detail action (native); never invent a Detail route for unmatched data, and never open a real purchase link in automation.
- If the catalogue fetch fails, show "Song details unavailable" while valid offers stay usable.

## States

| State / dependency | Web behavior |
|---|---|
| Populated | Title-sorted offers, New / Leaving Tomorrow badges, original cover art |
| Narrow / wide | Compact external-link rows vs full-bleed artwork grid; wide list/grid preference |
| Empty vs error | Genuine empty message vs fetch failure (never interchangeable) |
| Hide / highlight | Hide Shop removes nav and effective highlights, retaining the saved preference |
| Cross-page | Shop badges and filters affect Songs and Detail; a WebSocket keeps rotation current |

## Open gaps (all platforms)

WebSocket rotation updates, Shop filters beyond In Shop / Leaving Tomorrow, quick-link rail, profile-dependent sorts, wide sidebar Shop entry, performance with many real images.

Native addition (not on the web, issues #19, #376): a page-local Item Shop Filter sheet (Windows: flyout) with New / Available / Leaving Tomorrow switches on Apple, Android and Windows. Shared semantics: *Available* = neither New nor Leaving Tomorrow; the switches are **include toggles that start on**, like the Songs Item Shop and Double Bass include toggles: a fresh filter and Reset have every switch on and list every offer, turning a switch off hides that group (an offer in two groups hides only when both are off), the filter counts as active only while a switch is off, and every switch off shows the no-match card. A platform that saved the older "show only" switches migrates them once without changing which offers show (all off → all on; any on → the same groups on, the rest off). Wire flags (works with highlighting off), live apply, and a no-match Reset card distinct from the empty Shop. See [ios.md](ios.md), [android.md](android.md), [windows.md](windows.md).
