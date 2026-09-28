# Songs — iPhone notes

> **What:** what the iPhone Songs page implements, native decisions that differ from the web, gotchas and open gaps. **Read when:** changing Songs on iPhone. Behavior: [spec.md](spec.md). Wave 1 task list: [PROGRESS.md](../../../PROGRESS.md) (Lane S).

## Implemented (partial)

- Live public Songs by default (728 songs decoded on 2026-09-25); fixtures via loopback override.
- `.searchable` native search pill (was an in-page capsule row); title-ordered list by default, scene-owned instrument filter (now applied via [Filter](../../controls/songs-filter/ios.md), not its own toolbar Menu), Detail/Solo navigation, accessible notice when a publication change or hidden instrument clears a route/filter.
- `.festivalRootChrome(session:)` owns the top-right profile button and (drawer, Lane A) — Songs no longer keeps its own profile button/sheet or an Item Shop toolbar button; Shop is reached from the drawer. The in-page "Choose Profile" empty state uses `@Environment(\.openProfile)`.
- Sort + Filter are a `ToolbarItemGroup(.topBarTrailing)` (a `ToolbarSpacer` separates them from the profile button on iOS 26); both tint gold when their applied choice is non-default.
- Sort: Title/Artist/Year/Duration + conditional Item Shop with Leaving/In/Not sections ([songs-sort/ios.md](../../controls/songs-sort/ios.md)).
- Filter: selected-player Shop toggles, score/FC checks, and (new) the single-chart Instrument picker, all in one Apply/Cancel/Reset draft, matching web's `FilterDraft.instrumentFilter` ([songs-filter/ios.md](../../controls/songs-filter/ios.md)).
- Right-edge Contacts-style section-index scrubber for Title/Artist/Year sorts; animates in/out when the sort mode does or doesn't have a meaningful key ([songs-section-index/ios.md](../../controls/songs-section-index/ios.md)).
- Rows are `festivalGlass(.card)` cards with tightened List row insets (2pt vertical) to match the web list's 2pt virtual row gap; cards drop the trailing disclosure chevron per Apple HIG (see Native decisions).
- Selected-player card: status chips ([chips](../../controls/songs-instrument-status-chips/ios.md)) or typed metadata pills ([metadata](../../controls/song-score-metadata/ios.md)); duration (e.g. 6:06) shown, including at accessibility sizes.
- `#if DEBUG` env `FST_DEBUG_SONG=<title-or-songId>` auto-pushes that song's Detail once the catalogue loads (local `.navigationDestination(item:)`, independent of the shared route stack) so `tools/ios_sim.py shot`/`drive` can reach Song Detail without manual navigation.

## Native decisions (deliberate deviations)

| Web | iPhone | Why |
|---|---|---|
| Lower Search/Sort dock, bottom sheets | Large-title `.searchable`, top toolbar Sort/Filter, full-height system sheets | Bottom toolbar collided with the Liquid Glass tab |
| Row is a link with a trailing chevron in most lists | Card-style row **is** the tap target, no chevron | Apple HIG: card rows drop the disclosure indicator. Implemented as an invisible, stretched `NavigationLink` behind the visible glass card (`ZStack` + `.opacity(0)`), combined into one VoiceOver stop — a List row's automatic accessory only appears for a *visible* `NavigationLink` label |
| Icons-off fallback to Lead even if hidden | First **visible/filtered** chart | Respect Settings |
| Last Played hidden under Title | Toggle-controlled date under Title | Until Last Played sort ships |
| Long title marquee | Wraps full title | Legibility at large text |
| First-run Filter Songs carousel | Absent | Pending |
| Instrument selector always visible in Filter | Instrument section only when a player is selected | Matches web's practical gating: Filter itself only opens with player/Shop data on mobile |

## Gotchas

- `TabView` retains a failed Songs view: its `.task` is keyed by publication **and visibility** and must retry when the tab returns, even if Settings already fetched a valid catalogue at the same generation. A cancelled older request must not overwrite the replacement with a late error.
- Service errors use `ServiceUnavailableView` (scrolls at large text; scroll the error view itself). `.refreshable` only on the loaded List.
- No-results view uses a wrapping title and bright semantic text; an instrument-only empty result says no songs **match the filters**.
- Grouped (Shop-sort) and section-indexed (Title/Artist/Year) Lists share one `songRowInsets` (2pt vertical, 16pt horizontal) so cards stay tight and clear the floating tab.
- At AX sizes, only the chip-visible row mode stacks title/artist full-width above art and chips.
- Real Liquid Glass (`glassEffect`, iOS/macOS 26+) does not reproduce through `NSHostingView.cacheDisplay`: hosted pixel tests that render a `festivalGlass` surface must force the deterministic fallback (`fst.accessibility.moreContrast = true` in the test's `UserDefaults`/`@AppStorage`), or every state renders byte-identical. See `deterministicGlassDefaults()` in `SongScreenStatesTests.swift`/`SelectedSongRowRenderTests.swift`.
- UI tests: query `fst.songs.list`; see [xcuitest pitfalls](../../testing/apple/xcuitest.md).

## Online-only cleanup

Done for this page: Songs (and Song Detail/SongScorePreview/SongPathsSheet/Shop) no longer render the `OfflineDisclosure` warm-cache banner for `isStale` payloads. The separate "showing live songs without publication verification" notice (headerless/unverified-but-live responses) is unrelated and unchanged, as are the publication-mismatch/paused-filter notices required by `AGENTS.md`'s safety invariants.

## Open (iPhone)

Grouped-Songs full audit (intermittent nil-element Dynamic Type) and saved-Shop-sort + failed-Shop contrast ([accessibility](../../testing/apple/accessibility.md)); landscape and largest type across modes; quick links; selected-profile sorting; band rows; invalid-score action; keyboard/pro-keys `InstrumentIcon` variant (song model has no `sig` field yet); the new section-index scrubber has no XCUITest coverage yet (unit-tested in Core only).
