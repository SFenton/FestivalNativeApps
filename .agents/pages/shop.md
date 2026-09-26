# Item Shop (`/shop`) - partial Apple route

Source: `FortniteFestivalWeb/src/pages/shop/ShopPage.tsx:41-190`,
`src/pages/shop/components/ShopCard.tsx:18-109`,
`src/contexts/ShopContext.tsx:30-129`,
`src/hooks/data/useShopState.ts:1-61`,
`src/components/shell/mobile/BottomNav.tsx:45-75`,
`FSTService/Api/SongEndpoints.cs:244-255`,
`FSTService/Api/ShopCacheService.cs:48-92`, and
`FSTService/Scraping/ShopUrlHelper.cs:14-34`. Review the pinned dirty
source snapshot before a parity claim.

**Wire and navigation:** Keyless, publication-aware `GET /api/shop`
returns `count`, enriched `songs`, `isNew`, `leavingTomorrow`, official
`shopUrl` and optional update metadata. ETag/304 is valid only within
the current publication. Validate count/unique IDs, nonempty titles
and **HTTPS `www.fortnite.com/item-shop/jam-tracks/`** outbound links;
invalid bytes must not enter a headerless offline snapshot. A bounded
opt-in native Swift read on 2026-09-25 decoded 133 real items, one New
and one Leaving Tomorrow, with response provenance and no privileged
key. It logged no title, ID, URL or artwork. This endpoint works
independently of Cloudflare-denied profile/rank searches.

The PWA Shop is a route reached through its wider nav/hamburger, **not**
a fourth no-profile mobile tab. Native Apple pushes Shop within the
Songs tab from an accessible top Shop action, retaining the three system
tabs. A matched catalogue record enables a separate native Song Detail
link; a validated Shop URL has its own external action. Never open an
external purchase link in fixture automation or turn missing
catalogue data into an invented detail route. If catalogue fetch fails,
show a visible "Song details unavailable" warning while the valid Shop
offers remain usable.

| State / dependency | React behavior | Current native Apple and pending work |
|---|---|---|
| Initial/populated | Title-sorted offers, New/Leaving Tomorrow and original cover art | Typed feed, distinct badges, safe external links, in-app Detail and source ordering |
| Narrow/wide | Compact external-link rows vs full-bleed artwork grid; wide list/grid preference | Native compact list, regular lazy full-bleed grid/list toggle; accessibility-size iPad reflows to list to avoid clipped artists |
| Empty/error | Genuine empty message vs fetch failure | Explicit empty card or scalable unavailable/Retry, not an empty-data fallback for HTTP errors |
| Hide/highlight | Hide Shop nav/effective highlights while retaining saved preference | Native Settings removes Shop action/resets its route with notice; badge/border highlighting updates and its saved value survives hiding |
| Offline | Web HTTP/React query state | Native validated Shop rows and recent original covers survive actual warm listener loss as "publication unverified"; both disappear after process relaunch |
| Cross-page | Shop badges and filters affect Songs/Detail; WebSocket keeps rotation current | **Not ported:** native Song cards/Detail/shop sort/filter and live updates do not yet consume Shop membership |

**Matched fixture observation:** Two selected source WebKit tests capture
phone 390x844 list and tablet 820x1180 grid from the same synthetic
two-offer feed as the native iPhone/iPadOS 26.5 captures. After comparing
the first native screenshots, compact rows were condensed to art/title/
badge/bag actions and grid tiles made full-bleed with readable scrims
and red/gold accents. Apple system title/back/tab/sidebar chrome and
a separate Detail action intentionally differ; the PWA's source grid
card itself opens the official Shop URL. This is a structural
comparison, **not** pixel or full feature parity.

**Evidence and gaps:** `ShopCatalogTests` prove official-link
validation, count/order, pin/304, malformed/oversized input rejection
and warm-only memory. `tools/mock_service.py` serves deterministic
demo/empty/503/white-art states and an opt-in local port 8773 that
closes only after the device test confirms actual artwork pixels.
The selected native populated/navigation, Settings propagation,
empty/error and warm-offline/cold-expiry cases passed on iPhone and
iPadOS 26.5. Loaded, empty, error and warm-offline visible Shop states
passed unwaived `.all` audits after large-text reflow and the bounded
strong recent-art cache; they do **not** certify every card, external
link focus, macOS GUI, Duo posture, animation performance, landscape,
all Settings combinations or Android/Windows. iPad sidebar Shop entry,
global search/profile header, push-notification/shop WebSocket,
Shop-aware Songs/Detail and full-source coverage remain pending.
