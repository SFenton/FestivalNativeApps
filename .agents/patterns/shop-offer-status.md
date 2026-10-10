# Item Shop offer status

> **What:** how a song's Item Shop state (New, Leaving Tomorrow) shows on Songs rows, Item Shop list rows, Item Shop grid cards and the first-run demos that replicate them: the gold or red outline, the only visible indicator (Leaving Tomorrow), and the spoken state. **Read when:** changing a Shop or Songs row's badge, outline, trailing icons or accessible name, or adding a surface that shows Shop offers.

Status: **current**, 2026-10-10. Provenance: operator 2026-09-28 (no visible New chip on Songs rows), #562 (no New badge on Shop rows and cards, every platform).

## Intent

New and Leaving Tomorrow look the same wherever a Shop song appears. New is a calm gold outline; only Leaving Tomorrow, which asks people to act today, earns a visible indicator. Screen-reader users still hear both states.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx` (`shopHighlightGold`, `leavingCircleMobile`) | Row outline: red Leaving, gold New, green in Shop. `leavingIndicator` adds the "Leaving Tomorrow" pill (wide) or the timer circle (`IoTimerOutline`, compact) **only** for Leaving; then the bag and chevron. No New indicator. |
| `FortniteFestivalWeb/src/pages/shop/ShopPage.tsx` (`shopHighlightGold`) | The Shop list passes `shopHighlightGold` / `shopHighlightRed` to the shared `SongRow`. |
| `FortniteFestivalWeb/src/pages/shop/components/ShopCard.tsx` (`shopHighlightGold`, `leavingTomorrowPill`) | Grid card: red or gold outline; a "Leaving Tomorrow" pill only when leaving. No New pill. |

The web gives New no accessible text at all; the natives add it (R3).

## Rules

1. **R1. New is the gold outline alone.** A New song shows the gold outline/pulse and nothing else: no chip, pill, sparkles or other glyph, on Songs rows, Item Shop list rows, Item Shop grid cards and first-run demo rows. Owner decisions: Songs rows (operator, 2026-09-28) and the Item Shop ("Stars icon is unexpected and not needed … No stars icon, compare to web", #562).
2. **R2. Only Leaving Tomorrow gets a visible indicator.** Leaving Tomorrow keeps its red outline plus a visible indicator: the red clock circle on rows (web `leavingCircleMobile`; Android and Windows list rows use the red "Leaving Tomorrow" pill, web `leavingPillDesktop`) and the red "Leaving Tomorrow" pill on grid cards (web `leavingTomorrowPill`). On rows it sits before the official Item Shop bag and the chevron (web `externalIndicator` order). Songs rows keep the in-Shop bag for every Shop song.
3. **R3. The state stays spoken.** Removing the glyph never removes the state from assistive technology: a New row or card says "New" (Songs rows "Item Shop: New") in its accessible name or state, and Leaving rows say "Leaving Tomorrow". HIG Color: "**Avoid relying solely on color** to differentiate objects, indicate interactivity or communicate essential information; be sure to also convey it another way, like text labels or glyph shapes" (should). On the Shop page the outline's presence (not only its colour) separates New from plain offers, Leaving adds its glyph, and the spoken state covers VoiceOver, TalkBack and Narrator.
4. **R4. One component per platform.** Each platform draws the status through its canonical pieces below; a feature folder never adds its own New badge, Leaving pill or status marker.
5. **R5. Highlighting off or Shop hidden shows no state.** When Item Shop highlighting is off or the Shop is hidden, no outline, indicator or spoken state appears (Apple `ShopPresentationPolicy.highlight(for:hidden:highlightingDisabled:)`); the official link stays.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Spoken New with no visible badge (R1, R3) | `apple/Sources/FestivalUI/Features/Songs/SongRowView.swift` `ShopNewStatusMarker` (1 pt clear element: label plus `fst.shop.badge.new.<id>` / `fst.songs.shop-badge.<id>`), used by `SongRowView` (`shopBadge`, `shopOfferTrailing`) and the grid card's `offerBadge` in `ShopScreen.swift`; the grid card's name also includes the state (`cardAccessibilityLabel`) | `ShopListRow` `stateDescription = "New"` (`ui/shop/ShopScreen.kt`); Songs `ShopBadge` shows the bag, never a New glyph (`ui/songs/SongRow.kt` `shopBadgeIcon`) | `ShopOfferItem.Announcement` ends in "New" (`Festival.Core/ViewModels/ShopViewModel.cs`) |
| Leaving indicator (R2) | `SongRowView.swift` `ShopLeavingIndicator` (rows); `ShopScreen.swift` `offerBadge` (grid pill) | `ui/shop/ShopScreen.kt` `ShopBadgeLabel` (Leaving only) | `ShopOfferItem.ShowsPill` (Leaving only) applied by `ShopPage.xaml.cs` `ApplyBadge` |
| Outline (R1, R2) | `SongRowView` row border (`ShopRowPulseBorder`); grid card `ShopScreen.swift` `borderColor(for:)` | `ui/shop/ShopScreen.kt` `shopOutline` | `ShopOfferItem.Pulse` (`SongRowShopPulse`) |

Apple consumers: Songs rows, Item Shop list rows (`SongRowView` with `SongRowShopOffer`), Item Shop grid cards (`ShopScreen` in a regular-width window: iPadOS, macOS and the unfolded iPhone Duo) and the first-run Songs/Shop demos (`FirstRunNativeShopDemo`, `FirstRunShopDemos`, both through `FirstRunSongRow` → `SongRowView`). Tests: `ShopRowAccessibilityTests` (`newShopRowsDrawNoBadgeButStillSayNew`, `newShopCardsDrawNoPillButStillSayNew`, `shopRowsNameTheirActionsAndShopState`, `shopRowsReadInVisualOrderWithFullSizeBagTargets`), `ShopScreenRenderTests` (gold outline, no gold glyph) and the iOS `ShopJourneyTests` compact-row journey (clock before bag).

## Known debt

None.

## Guards (`tools/pattern_guard.py`)

- `shop-offer-status/apple-shop-new-glyph`
- `shop-offer-status/apple-songrow-new-glyph`
- `shop-offer-status/android-new-glyph`
