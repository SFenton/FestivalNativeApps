# Item Shop — iPhone notes

> **What:** iPhone implementation and decisions for the Shop route. **Read when:** changing Shop on iPhone (Lane S). Behavior: [spec.md](spec.md); offers/badges: [shop-offers/ios.md](../../controls/shop-offers/ios.md).

- `ShopScreen` is a pushed route (not a tab). Entry: the leading drawer (Lane A); removing the older Songs toolbar Shop button is a Lane S task ([PROGRESS.md](../../../PROGRESS.md)).
- List rows are the **shared Songs `SongRowView`** (issue #18; web `ShopPage` list renders the Songs `SongRow`): same glass card surface, 44pt art and one-line `MarqueeText` title + "artist · year · duration" that auto-scrolls when too long instead of wrapping (both lines wrap at accessibility sizes). `SongRowShopOffer` swaps the profile/score area for Shop's trailing **badge, bag slot, then chevron** (installed-PWA gap #17); ~60pt tall, 6pt apart. Red/gold `ShopRowPulseBorder` for Leaving/New, none for plain offers (web passes only `shopHighlightRed/Gold`). `ShopRowPolicy` draws the catalogue song when matched, else a display-only `Song(shopOffer:)` that never routes to Detail. Do not reintroduce a Shop-only row view.
- Text and the bag glyph use `FestivalText.primary` (white, operator 2026-09-28); only the decorative chevron is `FestivalText.deemphasized`.
- Row structure: the list is a `ScrollView` + `LazyVStack`, not a `List` (a `List` adds its own disclosure chevron *before* the bag). The Detail `NavigationLink` wraps the shared row, which reserves the bag slot (`ShopRowMetrics`); the official bag `Link` is a **sibling overlay** on that slot (never nested, per the one-action-per-row rule in [architecture](../../platforms/apple/architecture.md)). No catalogue match → no chevron, bag only. At accessibility sizes the bag becomes a labelled "Open Official Item Shop" action under the row.
- The loaded list fades in with the shared `festivalFadeInOnAppear()` (no fade under Reduce Motion).
- First-screen art: `load()` warms up to 12 covers (`ShopArtworkPrimePolicy`) through `FestivalSession.preparedArtwork` at the row's `maxPixels` (132) while the catalogue loads, bounded by 900 ms, like the Songs first-paint gate. Shared bounded caches only; nothing persisted.
- Hide Shop in Settings removes the action and returns an open Shop route to Songs with a notice.
- Explicit empty card vs scalable unavailable/Retry for HTTP errors.
- Structural comparison against web phone captures (390×844) only; not pixel parity.
- Warm "publication unverified" Shop rows after connection loss predate online-only; do not extend. The strong recent-art cache tier stays ([architecture](../../platforms/apple/architecture.md)).
- Open: full focus order, landscape, rapid-gesture races on device, Shop filters/WebSocket.
- **Load/reload fade (issue #71):** Shop runs the shared `FestivalReloadGate` on load and on a List/Grid switch, retry or publication change: old results leave at once, the spinner fades in, holds ≥400 ms, fades out (500 ms) and the results fade/stagger in; Reduce Motion swaps instantly. See [iPhone motion](../../design/apple/iphone.md#motion).
