# Public Shop offers (`fst.songs.shop`) — spec

> **What:** platform-neutral contract for Shop offer data, badges and highlight effects across Shop, Songs and Detail. **Read when:** touching Shop membership, badges, row borders or the official Shop link on any platform. Platform notes: [ios.md](ios.md). Route: [pages/shop](../../pages/shop/spec.md).

Source: `FortniteFestivalWeb/src/pages/shop/ShopPage.tsx:41-178`, `src/pages/shop/components/ShopCard.tsx:18-105`, `src/hooks/data/useShopState.ts:1-61`, `src/contexts/ShopContext.tsx:30-129`, `src/pages/songs/components/SongRow.tsx:348-364`, `src/pages/songinfo/SongDetailPage.tsx:322-323,634-638`, `FSTService/Api/ShopCacheService.cs:48-92`, `FSTService/Scraping/ShopUrlHelper.cs:10-34`.

## Contract

- `/api/shop` is independent of profile search and rankings. Membership, New and Leaving Tomorrow flags are validated; a missing/invalid envelope or untrusted outbound URL is an explicit error.
- Badges and borders reflect **effective** highlighting: hiding Shop or disabling highlights suppresses both but keeps the saved highlight preference.
- Never treat "empty", "data unavailable" and "catalogue details unavailable" as interchangeable.
- Decorate Songs rows only with flags from the **same observed publication** as the loaded catalogue; retained older Songs get no newer badges.

| Action / state | Expectation |
|---|---|
| Offer | Cover, title/artist/year, New or Leaving badge, official HTTPS Shop link, optional in-app Detail (validated catalogue song only) |
| Hide / highlight | Hidden: Shop route returns to Songs with a notice, highlight control disabled but retained |
| Empty / failure | True `count=0` → the platform's shared centred empty state with no card ([empty-error-states](../../patterns/empty-error-states.md) R8; web copy "No songs in the Item Shop"); HTTP 503 → unavailable/Retry, never success-shaped empty |
| Songs / Detail | Same-generation flags paint Songs red (Leaving) / gold (New) row borders; Detail shows the official action, availability badge and explicit Shop-fetch error; highlights off hides badges but keeps the link |
| Cancellation | A cancelled older Shop reply must not overwrite a newer offer or poison the next 304/ETag |
| Shop Filter (native, issues #19, #376) | New / Available (neither New nor Leaving) / Leaving Tomorrow include switches start on (every offer listed); turning one off hides that group from Shop's own list and grid live, in feed order (an offer in two groups hides only when both are off); active only while a switch is off; all off shows none; a filter with no matches shows the shared centred empty-state component with distinct filtered copy ("No Item Shop songs match your filters" / "Try changing your filters to see more songs."), **no card and no Reset button** ([empty-error-states](../../patterns/empty-error-states.md) R8, #377), never the genuine-empty state; the filter sheet's (Windows: flyout's) own Reset is the way back; saved older "show only" switches migrate without changing visible offers. Does not affect Songs or Detail |

Album art is decorative; titles, badges and actions carry their own labels. Registered IDs: `fst.songs.shop`, `fst.shop.{view-toggle,empty,offline,song-details-error}`, `fst.shop.{song,external,badge.new,badge.leaving}.*`, Apple Filter `fst.shop.filter{,.form,.new,.available,.leavingTomorrow,.reset,.done}`, Apple filtered-empty `fst.shop.filter-empty` (no empty-state Reset ID on any platform since #377; Android/Windows Filter IDs in their page notes), `fst.songs.shop-{badge.*,error,retry,offline}`, `fst.song-detail.shop{,-badge,-error,-offline}` plus the two Settings IDs.
