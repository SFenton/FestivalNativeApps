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
| Populated | Title-sorted offers (web today; natives: the saved Sort, see below), New / Leaving Tomorrow badges, original cover art |
| Narrow / wide | Compact external-link rows vs full-bleed artwork grid; wide list/grid preference |
| Empty vs error | Genuine empty message vs fetch failure (never interchangeable) |
| Hide / highlight | Hide Shop removes nav and effective highlights, retaining the saved preference |
| Cross-page | Shop badges and filters affect Songs and Detail; a WebSocket keeps rotation current |

## Open gaps (all platforms)

WebSocket rotation updates, Shop filters beyond In Shop / Leaving Tomorrow, quick-link rail, profile-dependent sorts, wide sidebar Shop entry, performance with many real images.

Native addition (not on the web, issues #19, #376): a page-local Item Shop Filter sheet (Windows: flyout) with New / Available / Leaving Tomorrow switches on Apple, Android and Windows. Shared semantics: *Available* = neither New nor Leaving Tomorrow; the switches are **include toggles that start on**, like the Songs Item Shop and Double Bass include toggles: a fresh filter and Reset have every switch on and list every offer, turning a switch off hides that group (an offer in two groups hides only when both are off), the filter counts as active only while a switch is off, and every switch off shows the no-match card. A platform that saved the older "show only" switches migrates them once without changing which offers show (all off → all on; any on → the same groups on, the rest off). Wire flags (works with highlighting off), live apply, and a no-match Reset card distinct from the empty Shop. See [ios.md](ios.md), [android.md](android.md), [windows.md](windows.md).

## Sort: native and web (agent decision, #379)

Owner (#379, split from #357): "Item Shop should have sorts by Title, Artist, Year, Duration, same as song list (multi-plat and web?)".

- **Modes:** Title, Artist, Year and Duration with Ascending / Descending, in the Songs Sort UI (the same sheet/flyout frame, mode radios and direction section as [songs-sort](../../controls/songs-sort/spec.md)). Default and Reset: Title ascending, the web Shop's order before #379. Changes apply live and persist (Apple `fst.shop.sortMode` / `fst.shop.sortAscending`; Android `fst.shop.sort` / `fst.shop.sortAscending`; Windows `shopSort` / `shopSortAscending`; web `localStorage` `fst:shopSort`); the choice is not a player setting, so deselecting a player keeps it.
- **Ordering:** the Songs catalogue comparator. Missing year or duration sorts as zero; ties break by title, then song ID, in the sort direction. The page filter runs first; grid, list and hinge-split layouts all show the one sorted list.
- **Duration:** `/api/shop` has no length, so Duration reads `durationSeconds` from the catalogue the page already loads, only when the catalogue observed the **same publication** as the Shop feed. While it loads, the page stays loading rather than reordering later. If it fails or the publications differ, the page shows title order in the chosen direction with a visible pause notice (`fst.shop.sort-paused`) and keeps the choice, like Songs' paused sorts.
- **Agent decision (#379, 2026-10-07; the owner may override with `/choose`): option B, the same sort modes on the native apps and the web** (option A was native only, with the web keeping title order). The web is the product source of truth and its Songs `SortModal` already offers these four catalogue modes with a direction, so one set of Shop sorts on every surface follows the owner's "same as song list" without making the web the exception. Native precedent: the Shop Filter (#19/#376) shipped natively first. Delivered on every surface: Apple ([ios.md](ios.md), the Songs `SongsSortSheet`; #431), Android ([android.md](android.md); #424), Windows ([windows.md](windows.md), the shared `SongSortForm` flyout; #428) and the web (`pages/shop/shopSort.ts`, `ShopSortModal`; SFenton/FortniteFestivalLeaderboardScraper#175). The shared rules, the full option table with guidance and the known debt are in the [catalogue-sort](../../patterns/catalogue-sort.md) pattern.
