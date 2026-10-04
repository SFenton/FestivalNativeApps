# Item Shop — Windows notes

> **What:** the Windows Item Shop page: navigation, layouts per window size, states and decisions. **Read when:** changing `windows/Festival.App/Pages/ShopPage*`, `ShopViewModel` or `FestivalSession.Shop.cs`. Behavior: [spec.md](spec.md); offers/badges: [shop-offers/windows.md](../../controls/shop-offers/windows.md).

## Implemented

- Navigation: an **Item Shop** pane item (`fst.nav.shop`, `AppSection.Shop`, own frame stack) after Leaderboards/Rivals/Statistics, as in the web desktop sidebar. Removed from the pane while Hide Item Shop is on (the shell returns to Songs if it was showing); a `/shop` deep link while hidden shows "Item Shop Is Hidden".
- `GET /api/shop` once per publication through `FestivalSession.LoadShopAsync` (shared with Songs and Song Detail); the catalogue loads best-effort for in-app links.
- Offers in title order. Grid tiles follow the web `ShopCard`: square full-bleed art, bottom scrim with title and artist, a **Leaving Tomorrow** pill top-right, and a gold (New) / red (Leaving) pulse ring (`ShopPulseRing`, the Songs rows' 2 s clock); list rows keep the New / Leaving badges. Highlighting off removes pills, badges and pulses but keeps the links.
- List rows are the Songs page's shared `Controls/SongRowCard` (issue #18): same card surface, 44 epx art, marquee title and subtitle, and pulse ring as Songs rows. `ShopPage` fills its trailing slot with the New / Leaving Tomorrow pill (`fst.shop.badge.new|leaving.<id>`) and the cart button, and hides the Songs bag on the art because the pill already names the Shop state. Do not reintroduce a page-local row template: Songs and Shop must look the same.
- The tile (`fst.shop.song.<id>`) opens Song Detail for catalogue songs (the official link otherwise); purchase is the tile's context menu item **Open in Item Shop** (`fst.shop.external.<id>`; right-click, Shift+F10 or press-and-hold), so tiles look like the web's `ShopCard` with no extra button (operator batch 6.9). List rows: row click → Song Detail, cart button (`fst.shop.external.<id>`) → official link.
- Reveal (operator batch 6.41/6.10): the visible layout waits behind a ring until the first 15 offers' art has decoded (≤ 900 ms), then fades its realized tiles/rows in with the shared stagger (`FadeIn.StaggerRealized`, repeater overload). A List/Grid switch scrolls to the top and replays this for the new layout, like the web's view toggle.
- Art: a recycled tile only takes the art of the load it still owns, and the shared byte cache forgets a download once it finishes even when every waiter had cancelled (a failed fetch used to stay "in flight" and replay its failure for the rest of the session: "art not loading", 6.9). A failed catalogue read keeps the offers with a "Song details unavailable" warning (`fst.shop.song-details-error`).
- **Filters** (issue #19): a **Filter** `DropDownButton` (`fst.shop.filter`, gold while a filter is on) left of the view toggle opens the Songs-style flyout: title, hint, `FilterToggleRow` ToggleSwitches **New**, **Available**, **Leaving Tomorrow** (`fst.shop.filter.new|available|leaving`) and a danger Reset (`fst.shop.filter.reset`); light dismiss/Esc closes it. Same semantics as Android: *Available* = neither New nor Leaving Tomorrow, union of switches, all off shows every offer, raw wire flags (highlighting off still filters), live apply, session-scoped `ShopViewModel.Filter` (not persisted). The count reads "N of M songs" while filtered; hiding every offer shows "No Matching Songs" + Reset Filters (`fst.shop.filter.empty`, `.empty-reset`), never the empty-Shop card.
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

Rotation push updates; Quick Links.

## Validation (issue #206, 2026-10-03)

Debug build, 3840×2160 at 150%, against the fixture service (every reachable state) and the live public service (keyless default origin, anonymous; 124 real offers on 2026-10-03). Tools: `a11y_matrix.py` (screenshot, Axe.Windows scan, 30-press Tab walk) with the `shop*` pages in `a11y.json` (empty/failed/catalogue-unavailable states use `tools/windows/shop_fixture.py`), keyboard journeys `kb-shop-grid`, `kb-shop-grid-open`, `kb-shop-list` (`a11y-keyboard.json`), and lock-tolerant UIA journeys `songs_journey.py --only shop,shop-compact,shop-states,shop-compact-states,shop-error,shop-hidden-states`. Every run: 0 Axe errors, focus never left the window, no repeated Tab stops.

| Configuration | Result |
|---|---|
| Compact 500×800 | ✅ Two-column grid, toggle hidden (also with List saved). Tab: Filter → grid (one stop) → out; Enter opens Song Detail. "Song details unavailable" notice now spans the same width as the header and tiles (was 12 epx short) |
| Medium 900×700 / wide 1440×900 | ✅ Grid (3/5 columns) and list; Filter and toggle both 40 epx (toggle was 32). Tab stops 9 (was one per tile); arrows move between tiles in two dimensions, Up/Down between list rows |
| Snapped left / maximized | ✅ Grid reflows (2 / 5 columns, 1040 epx cap left-aligned) |
| Dark (system) / Light (system) | ✅ Identical: the app is dark-only (deliberate, as on Songs) |
| Desert / Night sky contrast | ✅ Tile text gets system backplates; pills and focus use Highlight/HighlightText; filter flyout and empty card readable |
| Text 200% | ✅ after fix: the compact tile's **Leaving Tomorrow** pill was clipped to "Leaving Tomorro"; it now wraps. Filter flyout scrolls with Reset pinned; header, list badges and no-match state wrap |
| Display 100% / 150% | ✅ Same layout; tiles keep explicit square sizes |
| Keyboard only | ✅ `kb-shop-*`: Filter → toggle → grid → out, arrows inside, Shift+Tab back, Enter opens the filter flyout, Esc returns focus to Filter; Enter on a tile/row opens Song Detail, Alt+Left back |
| States | ✅ Loading, grid, list, filter flyout, filtered (New / Leaving / Available), no match + Reset Filters, empty Shop, failed feed + Retry (no Filter or toggle, was a stray toggle), catalogue unavailable notice, hidden (level-2 heading) |
| Narrator / UIA | ✅ Tiles are buttons named "title, artist · year[, Shop state]" (catalogue songs; others name the official-link action) with `fst.shop.song.<id>`; art and scrim are Raw; state titles are level-2 headings; "Item Shop, N songs" is announced after loading |

Deliberate deviations from the winui-design skill (kept):
- **Dark-only** (`RequestedTheme="Dark"`), matching the web app and the other Windows pages.
- **ItemsRepeater, not GridView**: the tiles need explicit square sizes and the shared staggered reveal; the grid copies GridView's keyboard model instead (`TabFocusNavigation="Once"` + XY arrows).
- **White title text on a black scrim** over decorative art, and the New pill's dark navy fill outside contrast themes: fixed contrast regardless of the art; contrast themes switch to system brushes.
- **No `x:Uid`** resources: the app is English-only for now.
- The loading ring has no visible caption; Narrator hears "Loading Item Shop" after 1 s.
