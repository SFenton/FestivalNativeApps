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
| Empty / failure | True `count=0` → scalable empty card; HTTP 503 → unavailable/Retry, never success-shaped empty |
| Songs / Detail | Same-generation flags paint Songs red (Leaving) / gold (New) row borders; Detail shows the official action, availability badge and explicit Shop-fetch error; highlights off hides badges but keeps the link |
| Cancellation | A cancelled older Shop reply must not overwrite a newer offer or poison the next 304/ETag |
| Shop Filter (native, issue #19) | New / Available (neither New nor Leaving) / Leaving Tomorrow switches narrow Shop's own list and grid live, in feed order; none selected shows all; a filter with no matches shows its own Reset card, never the genuine-empty state. Does not affect Songs or Detail |

Album art is decorative; titles, badges and actions carry their own labels. Registered IDs: `fst.songs.shop`, `fst.shop.{view-toggle,empty,offline,song-details-error}`, `fst.shop.{song,external,badge.new,badge.leaving}.*`, Apple Filter `fst.shop.filter{,.form,.new,.available,.leavingTomorrow,.reset,.done}`, `fst.shop.filter-empty{,.reset}` (Android/Windows Filter IDs in their page notes), `fst.songs.shop-{badge.*,error,retry,offline}`, `fst.song-detail.shop{,-badge,-error,-offline}` plus the two Settings IDs.
