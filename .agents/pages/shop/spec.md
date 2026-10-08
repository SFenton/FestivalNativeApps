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
| Populated | Title-sorted offers (web today; natives: the chosen Sort, Title ↑ by default, #379), New / Leaving Tomorrow badges, original cover art |
| Narrow / wide | Compact external-link rows vs full-bleed artwork grid; wide list/grid preference |
| Empty vs error | Genuine empty message vs fetch failure (never interchangeable) |
| Hide / highlight | Hide Shop removes nav and effective highlights, retaining the saved preference |
| Cross-page | Shop badges and filters affect Songs and Detail; a WebSocket keeps rotation current |

## Open gaps (all platforms)

WebSocket rotation updates, Shop filters beyond In Shop / Leaving Tomorrow, quick-link rail, profile-dependent sorts, wide sidebar Shop entry, performance with many real images.

Native addition (not on the web, issues #19, #376): a page-local Item Shop Filter sheet (Windows: flyout) with New / Available / Leaving Tomorrow switches on Apple, Android and Windows. Shared semantics: *Available* = neither New nor Leaving Tomorrow; the switches are **include toggles that start on**, like the Songs Item Shop and Double Bass include toggles: a fresh filter and Reset have every switch on and list every offer, turning a switch off hides that group (an offer in two groups hides only when both are off), the filter counts as active only while a switch is off, and every switch off shows the no-match card. A platform that saved the older "show only" switches migrates them once without changing which offers show (all off → all on; any on → the same groups on, the rest off). Wire flags (works with highlighting off), live apply, and a no-match Reset card distinct from the empty Shop. See [ios.md](ios.md), [android.md](android.md), [windows.md](windows.md).

Native addition, web to follow (issue #379): an Item Shop **Sort** with Title, Artist, Year and Duration and Ascending/Descending, through each platform's Songs Sort control ([songs-sort](../../controls/songs-sort/spec.md#item-shop-consumer-379)): same comparator and ties as Songs, live apply, Reset to Title ↑, one order for grid and list, and the choice persisted separately from the Songs sort. **Agent decision (#379, 2026-10-07; owner may override with `/choose`): option B, the native apps and the web Shop get the same four sorts** (not A, native only with the web title-only). The owner asked for "same as song list (multi-plat and web?)", and web behavior beats native copies, so the web Shop should reuse its Songs `SortModal` rather than leave a native-only feature. The web half lives in the web repo (not editable from this pipeline) and is a deferred follow-up; until it ships, the web keeps title order.
