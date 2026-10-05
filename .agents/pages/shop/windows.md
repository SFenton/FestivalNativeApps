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
- **Filters** (issue #19): a **Filter** `DropDownButton` (`fst.shop.filter`, marked by the shared `Controls/AppliedButtonState` like Songs: gold while a filter is on, Highlight/HighlightText under a contrast theme, UIA ItemStatus "Filters applied"; switch descriptions are the switches' HelpText) left of the view toggle opens the Songs-style flyout: title, hint, `FilterToggleRow` ToggleSwitches **New**, **Available**, **Leaving Tomorrow** (`fst.shop.filter.new|available|leaving`) and a danger Reset (`fst.shop.filter.reset`); light dismiss/Esc closes it. Same semantics as Android: *Available* = neither New nor Leaving Tomorrow, union of switches, all off shows every offer, raw wire flags (highlighting off still filters), live apply, session-scoped `ShopViewModel.Filter` (not persisted). The count reads "N of M songs" while filtered; hiding every offer shows "No Matching Songs" + Reset Filters (`fst.shop.filter.empty`, `.empty-reset`), never the empty-Shop card.
- States: loading, genuine empty card (`fst.shop.empty`), service status with Retry (`fst.shop.error`), hidden.

## Layouts

| Window | Layout |
|---|---|
| Compact (page < 640 epx) | Album-art grid forced (2 per row, as in the installed PWA; gap 7); toggle hidden |
| Medium / wide | Grid or list; **List View / Grid View** toggle (`fst.shop.view-toggle`, 40 epx like Filter) persisted in `AppSettings.ShopViewMode`, shown only while offers are on screen |

Grid geometry (`Domain/ShopGridMetrics`, web `ShopPage.tsx`): 2 columns below 600 epx, 3 from 600, 4 from 860, 5 from 1100; 10 epx gaps; the grid is at most 1040 epx wide (web `min(window, 1080) - 40`), left-aligned, so wide windows keep ~200 epx tiles; tiles get explicit square sizes from the scroller's width (a `UniformGridLayout` Fill stretch rounded an exact two-column fit down to one column at 150%). Tile text follows the web card: 16 epx scrim padding, 16 epx semibold title, artist below.

## Native decisions

| Web | Windows | Why |
|---|---|---|
| Shop in hamburger/sidebar | Pane item | Windows NavigationView is the app's sidebar |
| WebSocket rotation updates | Re-read on publication change | Online-only reads; no socket client yet |

## Open

Rotation push updates; Quick Links. UIA: `shop_journey.py` covers every shop-offers contract state at compact/medium/wide (see [shop-offers/windows.md](../../controls/shop-offers/windows.md#validation-issue-224-2026-10-04)); `songs_journey.py --only shop,shop-compact` covers grid, context-menu link, list toggle and Song Detail (never opens the real link).

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

## Validation (issue #237, 2026-10-04)

Check of #18 (list rows reuse the shared Songs `SongRowCard`; see [Songs](../songs/windows.md)): Debug build on a 3840×2160 host at 300% scale, against the live public service (keyless default origin, anonymous, 124 real offers, two Leaving Tomorrow) for every configuration, and against the fixture service for the reachable states. Tools: `a11y_matrix.py --live` (screenshot, Axe.Windows scan, Tab walk) with `shop-list` (now also at `maximized`) plus temporary page lists that scroll to a Leaving Tomorrow row or a long subtitle; the keyboard journey `kb-shop-list`; `shop_journey.py` (all 27 state × size drives pass, through UIA patterns, so also while the console is locked); `songs_journey.py --only shop,shop-compact` (these send real mouse clicks, so they cannot pass while the console session is locked: run them on an unlocked desktop; `shop_journey`'s `list`, `official-link` and `song-detail` cover the same paths); `tools/windows/tests` (172 pass); and 76 Shop unit tests. Every matrix run: 0 Axe errors, 9 Tab stops (search, profile, Shop, Settings, Filter, view toggle, row, cart, pane toggle), none outside the window, none repeated.

| Configuration | Result |
|---|---|
| Medium 900×700 / wide 1440×900 / maximized | ✅ Each row is the Songs card (glass surface, border, 44 epx art, title and subtitle as `MarqueeText`) with the Shop badge and a 44 epx cart button in the trailing slot; the Songs art bag is hidden because the badge names the state |
| Snapped left | ✅ at 150% the list shows. At 300% half the screen is 640 epx, so the page is compact and the grid is forced (by design, see Layouts) |
| Dark / Light (system) | ✅ Identical: the app is dark-only |
| Desert / Night sky contrast | ✅ Cards use Window/WindowText, the badge and pulse ring use Highlight/HighlightText, focus visuals are system colours |
| Text 200% | ✅ Title, subtitle and the **Leaving Tomorrow** pill all fit at 700 epx and wider; a subtitle too long for a 700 epx row ("Snoop Dogg ft. Pharrell & Uncle Charlie Wilson · 2003") scrolls as a marquee instead of being cut off or wrapping (PrintWindow frame capture, live) |
| Display 100% / 150% | ✅ Same layout; art and cart button keep their epx sizes |
| Keyboard only | ✅ Tab reaches the list once; Up/Down move between rows; Tab from a row reaches its cart button and Shift+Tab returns (now asserted in `kb-shop-list`); Enter opens Song Detail, Alt+Left returns to the list |
| Shop badges | ✅ New / Leaving Tomorrow pills and the red or gold pulse ring show on the shared row; the ring holds still when animations are off |
| Narrator / UIA | ✅ Rows are list items named "title, artist · year[, Shop state]" with `fst.shop.song.<id>`; the badge is text (`fst.shop.badge.*`); the cart is a button named "title, artist, Open Official Item Shop" (`fst.shop.external.<id>`); the marquee copies and pulse ring are Raw |

No product defects found; no app code changed. Deliberate deviations from the winui-design skill (kept, as in #206): dark-only theme; fixed 12/16 epx font sizes on the pill and cart glyph (they scale with Text size); no `x:Uid` resources (English-only for now).

## Validation (issue #238, 2026-10-04): Filter flyout

Debug build, 3840×2160 at 150%, `tools/windows/shop_fixture.py` for every state (2 offers: one New, one Leaving Tomorrow; none Available) and the live public service for evidence (keyless default origin, anonymous). Tools: `shop_journey.py --only filter` (compact / medium / wide), `a11y_matrix.py --only shop-filter,shop-filter-applied,shop-filter-empty --scan --tabs 12`, keyboard journey `kb-shop-filter` (`a11y-keyboard.json`, compact / medium). Every matrix run: 0 Axe errors, focus never left the window, no repeated Tab stops.

Found and fixed: the applied Filter button was gold only, so Narrator didn't hear the state (no ItemStatus, unlike Songs) and it vanished under contrast themes (gold resolves to WindowText; the page also never re-tinted on a theme switch); the switch descriptions (what *Available* means) weren't exposed to UIA. Both Filter buttons now use `Controls/AppliedButtonState` (moved out of `SongsPage`), Shop re-tints on `ContrastTheme.Changed`, and each switch's description is its `HelpText`.

| Configuration | Result |
|---|---|
| Compact 500×800 / medium 900×700 / wide 1440×900 | ✅ Flyout opens under Filter, fits the window; each switch filters live while open (New → 1 of 2, New + Leaving → union 2 of 2, Available → No Matching Songs + Reset Filters); Reset and clearing a switch bring every song back; reopening shows the same switches |
| Maximized / snapped left | ✅ Same flyout and states (Axe 0) |
| Dark (system) / Light (system) | ✅ Identical; the app is dark-only (deliberate) |
| Desert / Night sky contrast | ✅ after fix: applied Filter draws Highlight/HighlightText (was indistinguishable from off); flyout, switches and focus rings use system colours |
| Text 200% | ✅ Flyout scrolls with Reset pinned; Leaving Tomorrow is reached by Tab (focus scrolls it in); labels and descriptions wrap |
| Display 100% / 150% | ✅ Same layout |
| Keyboard only | ✅ `kb-shop-filter`: Enter opens with focus on New, Space toggles, Tab New → Available → Leaving → Reset, Enter on Reset clears, Shift+Tab back, Esc closes and returns focus to Filter, which then reports "Filters applied" |
| Narrator / UIA | ✅ Switches are ToggleSwitch (Toggle pattern) named by their labels with the description as HelpText; Filter is a button with ItemStatus "Filters applied" while filtered; the flyout title is a heading |

Deliberate deviations (kept): the Filter is a light-dismiss `Flyout` with live apply and no Done/Close button (Esc or clicking outside closes it, the Windows flyout pattern and parity with the Songs Filter, operator 2026-09-28); dark-only; English-only strings (no `x:Uid`).
