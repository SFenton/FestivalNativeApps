# Songs — iPhone notes

> **What:** what the iPhone Songs page implements, native decisions that differ from the web, gotchas and open gaps. **Read when:** changing Songs on iPhone. Behavior: [spec.md](spec.md). Wave 1 task list: [PROGRESS.md](../../../PROGRESS.md) (Lane S).

## Implemented (partial)

- Live public Songs by default (728 songs decoded on 2026-09-25); fixtures via loopback override.
- Inline `.searchable` list filter, prompt "Filter Songs" (separate from [global search](../../controls/global-search/ios.md), the header Search button); the A–Z scrubber is bottom-anchored so it does not jump when the header collapses; no visible "Item Shop: New" chip (the gold row outline marks it; VoiceOver keeps the label); title-ordered list by default, scene-owned instrument filter (now applied via [Filter](../../controls/songs-filter/ios.md), not its own toolbar Menu), Detail/Solo navigation, accessible notice when a publication change or hidden instrument clears a route/filter.
- `.festivalRootChrome(session:)` owns the top-right profile button and (drawer, Lane A) — Songs no longer keeps its own profile button/sheet or an Item Shop toolbar button; Shop is reached from the drawer. The in-page "Choose Profile" empty state uses `@Environment(\.openProfile)`.
- Sort + Filter are a `ToolbarItemGroup(Self.pageActionPlacement)` (`.topBarTrailing` on iOS, `.primaryAction` elsewhere); both tint gold when their applied choice is non-default. Per the [toolbar order rule](../../controls/app-navigation/ios.md#toolbar-order-rule-tab-roots), Songs ends its own `.toolbar` with `FestivalRootTrailingItems(session:)` and applies `.festivalProvidesRootTrailingItems()` so the shared bell+avatar capsule (which owns its own `ToolbarSpacer`) stays the rightmost item: `[drawer] … [sort] [filter] [quick links] [bell] [avatar]`.
- Duration and Item Shop sorts show a **Quick Links** toolbar menu ([quick-links/ios.md](../../controls/quick-links/ios.md)); Title/Artist/Year hide it because the section-index scrubber already owns jump navigation there.
- Sort: Title/Artist/Year/Duration + conditional Item Shop with Leaving/In/Not sections ([songs-sort/ios.md](../../controls/songs-sort/ios.md)).
- Filter: selected-player Shop toggles, score/FC checks, and (new) the single-chart Instrument picker, all in one Apply/Cancel/Reset draft, matching web's `FilterDraft.instrumentFilter` ([songs-filter/ios.md](../../controls/songs-filter/ios.md)).
- Right-edge Contacts-style section-index scrubber for Title/Artist/Year sorts; animates in/out when the sort mode does or doesn't have a meaningful key ([songs-section-index/ios.md](../../controls/songs-section-index/ios.md)).
- Rows are `festivalGlass(.card)` cards with tightened List row insets (2pt vertical) to match the web list's 2pt virtual row gap; cards drop the trailing disclosure chevron per Apple HIG (see Native decisions).
- Selected-player card: status chips ([chips](../../controls/songs-instrument-status-chips/ios.md)) or typed metadata pills ([metadata](../../controls/song-score-metadata/ios.md)); duration (e.g. 6:06) shown, including at accessibility sizes. The pill order honors Settings' `fst.settings.songRowVisualOrder` (`SongProfileCardPolicy.reordered`), applied after visibility filtering so the reorder never adds, drops or invents a field.
- `#if DEBUG` env `FST_DEBUG_SONG=<title-or-songId>` auto-pushes that song's Detail once the catalogue loads (local `.navigationDestination(item:)`, independent of the shared route stack) so `tools/ios_sim.py shot`/`drive` can reach Song Detail without manual navigation.
- Row title and artist·year·duration use `Design/MarqueeText.swift` (2026-09-28), a native port of web's `MarqueeText.tsx`/`MarqueeText.module.css`: auto-scrolls a two-copy track only once measured wider than its row, dwell-pauses at each end like the web keyframe, falls back to static `.truncationMode(.tail)` under Reduce Motion, and stops (no timer) once its row leaves the List or the scene backgrounds. This replaced a `.fixedSize(horizontal: false, vertical: true)` that let long combinations (e.g. "6 Foot 7 Foot"'s artist/year/duration on folded Duo) wrap to a second line instead of staying on one. Pure cycle math lives in `MarqueeTiming` (unit-tested, `MarqueeTimingTests`); should also be adopted by `Features/SongDetail/SongDetailScreen.swift`'s title header (web's `SongInfoHeader.tsx`) and `Features/Suggestions/SuggestionCategoryCardView.swift` (web reuses the same `SongInfo.tsx` there) — both outside this lane's ownership.
- Shop/Duration sort groupings are now real `List` `Section`s (matching the Title/Artist/Year section-index groups) instead of a plain row styled to look like a header; see [quick-links/ios.md](../../controls/quick-links/ios.md) for why they still register as Quick Links rather than a scrubber section.
- First reveal waits for the catalogue **and** the first ~12 visible rows' artwork to decode (bounded to 900ms so slow/unreachable art can never block it), then cross-fades in — a native-only addition (the web has no equivalent first-paint gate; it reveals rows immediately and fades each `<img>` in independently). See `SongsScreen.primeFirstArtwork(for:)`.

## Native decisions (deliberate deviations)

| Web | iPhone | Why |
|---|---|---|
| Lower Search/Sort dock, bottom sheets | Large-title `.searchable` filter; Filter and Sort as floating round glass buttons above the tab bar (Duo/iPad/Mac: toolbar); global Search in the header; full-height system sheets that apply immediately with Done | A `.bottomBar` toolbar renders behind the Liquid Glass tab |
| Row is a link with a trailing chevron in most lists | Card-style row **is** the tap target, no chevron | Apple HIG: card rows drop the disclosure indicator. Implemented as an invisible, stretched `NavigationLink` behind the visible glass card (`ZStack` + `.opacity(0)`), combined into one VoiceOver stop — a List row's automatic accessory only appears for a *visible* `NavigationLink` label |
| Icons-off fallback to Lead even if hidden | First **visible/filtered** chart | Respect Settings |
| Last Played hidden under Title | Toggle-controlled date under Title | Until Last Played sort ships |
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
- `primeFirstArtwork(for:)` only runs on the very first `.loading → .loaded` transition (`prior == nil` in `reload()`); pull-to-refresh and retries after an error that already had prior rows never re-block on artwork, matching the existing retain-on-error behavior.

## Online-only cleanup

Done for this page: Songs (and Song Detail/SongScorePreview/SongPathsSheet/Shop) no longer render the `OfflineDisclosure` warm-cache banner for `isStale` payloads. The separate "showing live songs without publication verification" notice (headerless/unverified-but-live responses) is unrelated and unchanged, as are the publication-mismatch/paused-filter notices required by `AGENTS.md`'s safety invariants.

## Root navigation-notice card (`fst.songs.navigation-notice`)

`SongsScreen`'s top-of-list notice card (2026-09-28 operator ask) is generic: it just shows whatever `navigationNotice` string the root passes it, and clears when dismissed or replaced. Root shell (`App/FestivalRootView.swift`, Lane W1's file, not this lane's) sets that string for three separate resets: publication change, selected-profile change ("Selected profile changed. Returned to Songs…") and Shop being hidden. The operator asked to remove only the **profile-change** notice; that is entirely a root-side change (deleting the `songsNotice = "Selected profile changed…"` assignment there). This page's card needed no change — it keeps showing the other two legitimate notices unmodified, and simply stops receiving the removed one once the root no longer sets it.

## Open (iPhone)

Grouped-Songs full audit (intermittent nil-element Dynamic Type) and saved-Shop-sort + failed-Shop contrast ([accessibility](../../testing/apple/accessibility.md)); landscape and largest type across modes; Quick Links for Year and any profile/band-scored sort (no native sort exists yet for those); selected-profile sorting; band rows; invalid-score action; the new section-index scrubber has no XCUITest coverage yet (unit-tested in Core only).

`Song.sig` (`"Guitar"`/`"Keyboard"`, `Song.usesKeyboardIcon`) is decoded and drives the keyboard/pro-keys `InstrumentIcon` variant in the instrument status chips. `Song.maxScores` (`"maxScores"`, keyed by the same service instrument ID as `Instrument.rawValue`, e.g. `"Solo_Guitar"`; not every chart has an entry) is decoded via `Song.maxScore(for:)` for a future Suggestions `near_max_*` family — unused elsewhere in this lane.
