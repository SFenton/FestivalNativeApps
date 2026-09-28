# Quick Links — iPhone notes

> **What:** the native iPhone design decision for Quick Links (jump to a section of a page), the shared API in `Common/QuickLinks/`, deliberate differences from the web, and a per-page adoption checklist. **Read when:** adding section navigation to any iPhone page, or adopting Quick Links on a page your lane owns.

## Verdict

**Portable, with no blockers.** Every web behavior has a native equivalent: an ordered section list, a jump with animated scroll, active-section tracking with jump ownership, and a shell-independent entry point. The platform provides `Menu`, `ScrollViewReader`, `onGeometryChange` and `accessibilityRotor`. Everything back-deploys to iOS 17, and nothing needs `if #available`. It shipped first on Leaderboards.

## Design decision

| Form factor | Presentation | Why |
|---|---|---|
| **iPhone** | A toolbar button (`list.bullet.indent`, label "Quick Links") opens a native **`Menu`**. Inside is one titled section with an inline `Picker` of sections, each with its icon; the active section is **checked**. | HIG (iOS 26): page actions live in the nav-bar toolbar, and the system gives them a Liquid Glass capsule. Menus are the standard way to choose one of a small set of destinations without leaving context. The checkmark is the native form of `aria-current`. Fluent's "jump list" anchor navigation maps directly onto it. A menu replaces both the web FAB (a web workaround for a missing toolbar) and the bottom-sheet modal (an extra dismiss step). |
| iPhone, very long or nested lists | Menus scroll, so the menu covers every current page. If a page ever exceeds ~15 items or needs depth > 1, present the same list in a `.festivalSheet(.compact)` with a `List` (checkmark + `aria-current` equivalent). | HIG: menus should stay short; a medium-detent sheet keeps context visible. `TODO(orchestrator)`: not built yet; no page needs it today. |
| iPad / Mac (Wave 4) | A persistent trailing **inspector** (`.inspector`) listing sections with the active one highlighted. It collapses back to the toolbar `Menu` in compact width. | This matches the web ≥1440 px rail. HIG endorses inspectors for persistent secondary navigation in regular width. The controller and tracker are shared; only `QuickLinksMenu` changes to an inspector list. |

- **Songs:** the right-edge section index scrubber ([songs-section-index](../songs-section-index/ios.md)) owns alphabetical and year navigation. Quick Links must **not** duplicate it. Show the Jump menu only for sort modes where the scrubber is hidden (Duration, Item Shop, and the future score/FC/percentile/stars/season/intensity/difficulty sorts), using the web bucket labels. For Title, Artist and Year, the scrubber alone is the HIG section-index pattern. Web has no scrubber, so this split is native-only.

## Deliberate differences from the web

| Web | Native | Why |
|---|---|---|
| Mobile FAB, header ActionPill and modal | One toolbar `Menu` on every width class | System chrome over custom floating buttons ([liquid-glass.md](../../design/apple/liquid-glass.md) rule 1) |
| Appears with ≥ 1 item on some pages | Needs ≥ 2 sections (`QuickLinks.minimumSectionCount`) | A one-item jump does nothing (HIG: hide inert controls) |
| Hidden until the page is loaded | Leaderboards shows its menu while cards are still loading | Its skeleton cards are stable anchors. Other pages should still gate on load if their sections move |
| 120 ms (Player: 80 ms) settle timer | Animation completion (`withAnimation(…completion:)`) marks the jump owned; under Reduce Motion the jump is instant and settles on the next main-actor turn | Deterministic; no timers |
| Lands 32/16 px below the top | `scrollTo(id, anchor: .top)` aligns with the safe-area edge under the glass bar | `ScrollViewReader` has no offset. The bar's scroll-edge effect provides the separation. The activation line stays at 16 pt |
| Target with an unknown top cancels the jump | The target is held while scrolling even if a lazy stack hasn't built it yet | Lazy containers build views on demand |
| Keyboard focus trap and Escape | System menu focus and dismissal; VoiceOver **"Quick Links"/page-title rotor** over every section; selection haptic | These are the native equivalents |
| Settings `showButtonsInHeaderMobile` | Not ported for Quick Links | The toolbar button is the only entry point. The setting never affected quick links on web ([spec](spec.md#related-settings)) |
| Rivalry quick links unreachable on mobile (web bug) | Offer them | Fixes a web gap rather than copying it |

## API (`apple/Sources/FestivalUI/Common/QuickLinks/`, logic in `FestivalCore/QuickLinks.swift`)

```swift
@State private var quickLinks = QuickLinksController()                      // 1
ScrollView { LazyVStack { ForEach(items) { card($0).quickLinkSection(section($0)) } } }  // 2
    .quickLinks(quickLinks, title: "Leaderboards Quick Links", sections: sections)
    .toolbar { QuickLinksToolbarItem(quickLinks) }                          // 3
```

- `QuickLinkSection(id:title:icon:depth:)` (Core). The icon is `.system("sf.symbol")` or `.instrument(Instrument)`. Reuse the web `id` strings.
- `.quickLinkSection(_:)` / `.quickLinkSection(id:title:symbol:)`: apply it to the view a `ForEach` returns. It sets `.id` as the **outermost** modifier, so lazy stacks can scroll to sections they haven't built yet. It also reports the frame, registers the section for discovery, and adds a rotor entry.
- `.quickLinks(_:title:sections:activationOffset:)`: goes on the `ScrollView` or `List`. It wraps the view in a `ScrollViewReader`. Pass `sections:` for lazy containers (`LazyVStack`, `List`). Omit it for eager `VStack` pages, which then use sections discovered in tree order.
- `QuickLinksToolbarItem(_:placement:)`: add it inside the page's own `.toolbar`. It coexists with `festivalRootChrome` and page actions. `QuickLinksMenu` is the same button for use outside a toolbar.
- `QuickLinksController.jump(to:)` can be called from custom UI, such as an in-page link to a section.
- Pure rules (Swift Testing, `QuickLinksTests`): `QuickLinks.isAvailable`, `ordered`, `naturalActive`, `isVisible`, `isReachable`, and the `QuickLinkTracker` phases `idle → scrolling → owned`.
- Test IDs: `fst.quick-links.open` (the button; its value is the active title) and `fst.quick-links.item.<id>`. Menu items are also tappable by label in `ios_sim.py drive`.
- Measured frames are `@ObservationIgnored`, so scrolling redraws only when the active section changes.

## Adoption checklist (owning lanes)

Apply the three lines above. Mirror the web ids, labels and order from the [spec table](spec.md#per-page-items). Build `sections` from the same arrays the page iterates.

| Page / native file (owner) | Container | Sections (id → title, icon) | Notes |
|---|---|---|---|
| Leaderboards `Features/Leaderboards/LeaderboardsScreen.swift` (**done**, Lane Q) | `ScrollView`+`LazyVStack` | `instrument:<rawValue>` per visible instrument (`.instrument`), `band:<BandType.rawValue>` (`person.3.fill`) | Add `rank-history` first and a promoted band once native has the rank chart and band profiles |
| Songs `Features/Songs/SongsScreen.swift` (Lane S) | `List` (already in `ScrollViewReader`; replace it with `.quickLinks`) | Port `songQuickLinks.ts` bucket rules to a Core `SongQuickLinkBuckets` keyed `<mode>:<token>`, title "{Sort} Quick Links" | Put `.quickLinkSection` on each `Section`. Pass `sections: []` (hides the menu) when the scrubber is visible. Keep the scrubber's `scrollTo` |
| Song Detail `Features/SongDetail/SongDetailScreen.swift` (Lane S) | `ScrollView` | `intensity` "Intensity" (`chart.bar.fill`), `score-history` "Score History" (`clock`), `instrument-<rawValue>` per visible, supported instrument, `band-<type>` Duos/Trios/Quads (`person.3.fill`) | Promote the selected band type first. Eager stack: `sections` optional |
| Player / Statistics `Features/Profile/PlayerProfileContent.swift` (Lane P) | `ScrollView` | `global` "Global Statistics" (`chart.bar.fill`), `instrument:<rawValue>` per visible instrument, `top-songs` "Top Songs" (`music.note`), `bands` "Bands" (`person.3.fill`) | The toolbar item sits beside Select Profile |
| Band detail `Features/Bands/*` (Lane N) | `ScrollView` | `members` "Members" (`person.3.fill`), `summary` "Summary" (`list.bullet`), `statistics` "Statistics" (`chart.bar.fill`), `rank-history` "Rank History" (`trophy.fill`), `songs` "Songs" (`music.note`) | Only once loaded without error |
| Compete `Features/Compete/*` (Lane R) | `ScrollView` | `leaderboards` "Leaderboards" (`trophy.fill`), `rivals` "Rivals" (`person.2.fill`) | Hide in the error state (web gap) |
| Rivals `Features/Rivals/*` (Lane R) | `ScrollView` | Song tab: `common` "Common Rivals" (`person.2.fill`), `combo` "{Combo} Rivals" (`music.note`), `<Instrument.rawValue>` "{Instrument} Rivals"; Leaderboard tab: `<Instrument.rawValue>` only | Rebuild `sections` when the tab changes |
| Rivalry (Lane R) | `ScrollView`/`List` | `<songId>:<instrument>:<index>` → song title per row in the `mode` category, instrument icon | Rows can be many, so pass `sections`. Use the compact sheet above ~15 rows once it exists |
| Rival Detail (Lane R) | `ScrollView` | `rival-category:<key>`: Closest Battles, Almost Passed, Slipping Away, Barely Winning, Pulling Forward, Dominating Them (no icon) | Only non-empty categories |
| Settings `Features/Settings/SettingsScreen.swift` (Lane M) | `ScrollView`+`LazyVStack` | `app-settings` (`gearshape.fill`), `diagnostics` (`info.circle`), `item-shop` (`bag.fill`), `show-instruments` (`music.note`), `show-metadata` (`list.bullet`), `version` (`info.circle`), `service-info` (`server.rack`), `first-run` (`sparkles`), `licenses` (`doc.text`), `refresh-profile-name` (`person.crop.circle`), `export` (`square.and.arrow.down`), `reset` (`trash`) | Match the conditions in the spec. **No Quick Links setting to add**; do not port `showButtonsInHeaderMobile` for this |

## Open issues

- On Leaderboards the system places the Quick Links button in the same trailing capsule as Rank By and the profile avatar. Lane A may want `festivalRootChrome`'s spacer to separate the profile bubble from page actions.
- No hosted or XCUITest coverage yet (UX-test phase). Rotor and haptics are unverified on device.
