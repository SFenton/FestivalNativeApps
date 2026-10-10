# Public Shop offers — Windows notes

> **What:** Windows Shop data, badges and publication rules across Shop, Songs and Song Detail. **Read when:** touching `ShopModels.cs`, `FestivalSession.Shop.cs` or Shop accents. Contract: [spec.md](spec.md).

- `ShopResponse.Validate` rejects count mismatches, duplicate (case-insensitive) or unsafe IDs, empty titles/artists and any link other than `https://www.fortnite.com/item-shop/jam-tracks/<slug>` (no port, credentials, query or fragment). Links open with `Launcher.LaunchUriAsync` only after that check.
- `FestivalSession` keeps one process-only feed with the publication it was observed under; `ShopOffersForCatalog` is non-null only when catalogue, Shop and client publications are equal (`SongRelatedPublicationPolicy`). Songs uses that for borders, filter and sort; mismatch pauses them with a notice.
- `ShopPresentationPolicy.Highlight`: Leaving Tomorrow wins over New; Hide Item Shop or Disable Shop Highlighting suppresses both (preferences kept).
- Colors: New = gold border/pulse (`FSTShopNewBrush`), Leaving Tomorrow = white on `FSTShopLeavingBrush`; contrast themes use Highlight/HighlightText (`Themes/Styles.xaml`).
- Item Shop pills (grid and list): only Leaving Tomorrow gets one (`ShopOfferItem.ShowsPill`, `fst.shop.badge.leaving.<id>`); New has no pill, only the gold pulse, and keeps "New" in the tile/row UIA name (issue #562, web `ShopCard` and `SongRow` leaving indicator).

## Validation (issue #224, 2026-10-04)

Every reachable contract state runs in `python tools/windows/shop_journey.py [--only NAME] [--sizes compact,medium,wide] [--shots DIR]` (`tools/windows/shop_fixture.py` switches the mock's Shop/catalogue between phases via `GET /__shop__/mode?shop=demo|empty|error|slow&songs=ok|error`; `slow` holds the read until the journey leaves it, so lock queuing cannot outrun the ring). How each state shows on Windows:

| State | Windows evidence |
|---|---|
| hidden | "Item Shop Is Hidden" heading (Level 2), pane item, Filter and List/Grid toggle gone |
| loading | one ring, `fst.shop.loading` (UIA name "Busy Loading Item Shop" while active); the reveal ring is collapsed while idle so UIA never reports an inactive ring. The journey starts the load from Retry inside the asserting drive, because a read held from launch can outlast the 30 s request timeout ("You're offline") while the drive waits for the shared desktop lock. |
| empty / failed | centred shared `EmptyStateView` (no card, #377) or service status + Retry; no Filter, no List/Grid toggle (fixed: the toggle used to show) |
| populated / new / leaving / grid | tiles named "Title, Artist · Year, New/Leaving Tomorrow"; Leaving pill `fst.shop.badge.leaving.<id>`; gold/red pulse |
| list | `fst.shop.list` rows with the Leaving pill (none for New, #562) and the cart button; toggle back to grid |
| offline | closed loopback port → "You're offline" + Retry (online-only: no offline cache UX) |
| unverified | catalogue read fails → offers kept under "Song details unavailable"; every tile names and opens the official link |
| official-link | context menu by Shift+F10 (`fst.shop.external.<id>`, never invoked in tests) and the list cart button |
| song-detail | tile → Song Detail "Open in Item Shop, Leaving Tomorrow"; a failed Shop read shows `fst.song-detail.shop-error` |
| highlight-disabled | no badges or pulse; links kept |
| filtered / filter-no-match | Leaving only → "1 of 2 songs"; Available only → "No Item Shop songs match your filters" + flyout Reset → "2 songs" |

Contrast: tile captions use `FSTShopTileTextBrush` on `FSTShopTileCaptionBrush` (white on the art scrim by default; WindowText on a Window plate under a contrast theme), with no inline colours. Under a contrast theme, the Leaving pill's text sets `HighContrastAdjustment=None`: it is already HighlightText on Highlight, and WinUI's automatic adjustment would otherwise paint a Window backplate inside the pill.

Per configuration (fixture runs: `shop_journey` and `a11y_matrix`; live runs: the anonymous public service):

| Configuration | Findings |
|---|---|
| Compact (500 epx), snap-left | 2-column grid, no List/Grid toggle (grid only), Filter kept; all compact scenarios pass; live snap-left shows the keyboard focus ring on the first tile |
| Medium, wide, maximized | 3–4+ columns; List/Grid toggle the same height as Filter; list rows with the cart button; all scenarios pass |
| Light / dark system theme | the app keeps its dark brand surface (no light theme), 0 Axe errors |
| Desert, Night sky | caption plate Window/WindowText, badges HighlightText on Highlight (fixed backplate), 0 Axe errors |
| Text 200% | title, count and buttons scale; long tile titles end in an ellipsis (full text in the UIA name); 0 Axe errors |
| Display 100% / 150% | layout identical in epx; 0 Axe errors |
| Keyboard | Tab order (medium/wide): search, profile, pane, Filter, List/Grid toggle, each tile, then wraps to the pane toggle. Compact drops the pane items and the toggle. Visible focus ring on tiles and buttons. Shift+F10 on a tile opens the official-link menu and Esc closes it; tiles invoke Song Detail through UIA Invoke |

Narrator order follows the UIA tree: the "Item Shop" heading (level 1), count, Filter, toggle, then the tiles in reading order. Each tile is one stop, and its name reads the title, artist and year, and badge.

Deliberate deviations from the winui-design/code-review skills: raw `FontSize` 16/12 on tile title and pills (web `ShopCard` parity) and English literals (the app has no `.resw` localisation yet).
