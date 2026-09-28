# Songs — iPhone notes

> **What:** what the iPhone Songs page implements, native decisions that differ from the web, gotchas and open gaps. **Read when:** changing Songs on iPhone. Behavior: [spec.md](spec.md). Wave 1 task list: [PROGRESS.md](../../../PROGRESS.md) (Lane S).

## Implemented (partial)

- Live public Songs by default (728 songs decoded on 2026-09-25); fixtures via loopback override.
- Title-ordered list, search, scene-owned instrument filter, Detail/Solo navigation, accessible notice when a publication change or hidden instrument clears a route/filter.
- Sort: Title/Artist/Year/Duration + conditional Item Shop with Leaving/In/Not sections ([songs-sort/ios.md](../../controls/songs-sort/ios.md)).
- Filter: selected-player Shop toggles + score/FC checks ([songs-filter/ios.md](../../controls/songs-filter/ios.md)).
- Item Shop toolbar action pushes Shop; New/Leaving borders **plus** accessible status icons ([shop-offers/ios.md](../../controls/shop-offers/ios.md)).
- Selected-player card: status chips ([chips](../../controls/songs-instrument-status-chips/ios.md)) or typed metadata pills ([metadata](../../controls/song-score-metadata/ios.md)); duration (e.g. 6:06) shown, including at accessibility sizes.

## Native decisions (deliberate deviations)

| Web | iPhone | Why |
|---|---|---|
| Lower Search/Sort dock, bottom sheets | Large-title search, top toolbar Sort/Filter/Shop, full-height system sheets | Bottom toolbar collided with the Liquid Glass tab |
| Conditional player tabs | Three tabs for now | Profile tabs pending (Lane A) |
| Icons-off fallback to Lead even if hidden | First **visible/filtered** chart | Respect Settings |
| Last Played hidden under Title | Toggle-controlled date under Title | Until Last Played sort ships |
| Long title marquee | Wraps full title | Legibility at large text |
| First-run Filter Songs carousel | Absent | Pending |

## Gotchas

- `TabView` retains a failed Songs view: its `.task` is keyed by publication **and visibility** and must retry when the tab returns, even if Settings already fetched a valid catalogue at the same generation. A cancelled older request must not overwrite the replacement with a late error.
- Service errors use `ServiceUnavailableView` (scrolls at large text; scroll the error view itself). `.refreshable` only on the loaded List.
- No-results view uses a wrapping title and bright semantic text; an instrument-only empty result says no songs **match the filters**.
- Grouped (Shop-sort) Lists: zero vertical row insets, 16pt horizontal gutters, so final cards clear the floating tab.
- At AX sizes, only the chip-visible row mode stacks title/artist full-width above art and chips.
- UI tests: query `fst.songs.list`; see [xcuitest pitfalls](../../testing/apple/xcuitest.md).

## Online-only cleanup

Warm-offline "last seen songs (publication unverified)" banners and snapshot fallbacks predate the online-only decision; removal is a Lane S Wave 1 task. Do not add new offline UI.

## Open (iPhone)

Grouped-Songs full audit (intermittent nil-element Dynamic Type) and saved-Shop-sort + failed-Shop contrast ([accessibility](../../testing/apple/accessibility.md)); landscape and largest type across modes; quick links; selected-profile sorting; band rows; invalid-score action; conditional tabs.
