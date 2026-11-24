# First-run experiences — iPhone notes

> **What:** the SwiftUI carousel, seen-state store and Settings replay as built, decisions and
> open gaps (Lane F). Spec: [spec.md](spec.md).

## UIKit live previews

- The Song List slide reuses the native Songs card and row, with the shared bounded
  catalogue selection and row-swap timing. Without usable catalogue songs it shows
  redacted rows, never invented titles. It does not expose preview rows as actions;
  the slide's narration is one static-text element.
- Only an active, visible slide can rotate, and decorative artwork stops under Low Data
  Mode or opaque presentation. Reduce Motion freezes rotation. HIG
  [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
  recommends onboarding that is optional and focused on the app's actual experience.
- The three Songs Shop slides explain sample statuses on catalogue rows, without looking
  up Shop membership or exposing purchase actions. They use the shared
  [Shop offer status](../../patterns/shop-offer-status.md) components; inactive previews
  and Reduce Motion keep the outline still ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- The Item Shop guide shows a three-column artwork overview and native catalogue rows
  for the three highlight lessons. A loaded Shop feed from the catalogue's observed
  publication can put Shop songs first; the guide does not fetch offers. The green,
  gold, and red phases are examples, not a report of the displayed songs' offer states.
  Use the shared 60 ms tile and 80 ms row entrance intervals. The narration is the only
  slide element exposed to VoiceOver; demos never open the store
  ([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)).
- The Songs Instrument Icons and Song Metadata slides render the shared sample chips and
  score fields on catalogue rows. Their examples do not read the user's scores or apply
  the saved visual order. They rotate on the same clock as Song List. Both renderers
  keep those illustrative rows and their fields out of the accessibility tree; the
  narration explains them instead ([HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)).
- In both renderers, decorative catalogue rows keep artwork and illustrative Shop styling,
  but omit the active player's or band's score fields and load status. The Instrument Icons
  and Song Metadata lessons use their own sample scores. This does not change the publication
  checks for rows in the real Songs list.
- The Score History overview uses the [shared Score History row](../../patterns/leaderboard-row.md)
  with the same illustrative scores as SwiftUI. Rows cascade before the text and are
  visible immediately under Reduce Motion ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- Song Info's two chart lessons draw the same three sample accuracy bars, with
  score annotations or a selection outline and detail strip. They share the
  [UIKit chart date axis](../../patterns/chart-date-axis.md), not the live chart's
  score axis or loader. Only the active selection lesson rotates: it uses the
  shared 2.5 s wait and 300 ms detail fades, and rests on the first bar under
  Reduce Motion. The narration is the only accessible element in the slide
  ([HIG Charts](https://developer.apple.com/design/human-interface-guidelines/charts):
  "Hide visible axis and tick text labels from assistive technologies").
- Optimal Paths reuses the viewer's collapsed selector labels with a local placeholder.
  It creates no native menus and never requests a path. The selectors enter before
  the placeholder; both are decorative, including at accessibility text sizes
  ([HIG Menus](https://developer.apple.com/design/human-interface-guidelines/menus),
  [HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)).
- Song Info's three Item Shop lessons use one bounded catalogue example and the
  real action's presentation policy: a green, gold or red disc in horizontal
  chrome, a plain labelled capsule on the folded rail or with highlighting off.
  In a narrow preview the capsule wraps its two words before compressing the
  song header. In a wide preview the label stays on one line.
  They redact song content without a catalogue, never fetch Shop offers or open
  the store, and use the shared three-second pulse only while active and motion
  is allowed. The narration describes the sample state without relying on colour
  or exposing the decorative button ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- Suggestions' category and scrolling lessons use the native category card with sample
  templates and bounded catalogue songs, never the selected player's recommendation feed.
  Rows cannot open songs and stay out of the narration; unavailable catalogue titles and
  artists are redacted. SwiftUI removes the decorative nodes from the pager's underlying
  accessibility tree instead of relying on a hidden ancestor. In short UIKit viewports,
  the rotating card keeps its heading at the top if it cannot fit centered.
  The single category swaps on the shared five-second clock using
  400 ms fades. The scrolling track uses the shared 100 ms wait, 30 pt/s glide and
  [scroll edge fades](../../patterns/scroll-edge.md). Keep both illustrations still
  under Reduce Motion, and stop decorative motion and artwork when the slide or scene
  is inactive, the network is constrained, or cards use opaque accessibility presentation
  ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- Song Info's View Player Scores and Top Scores Per Instrument lessons use the shared
  [score rows](../../patterns/leaderboard-row.md) and [View All button](../../patterns/view-all-cta.md)
  in one card with synthetic data. The history illustration mutes its last row;
  the leaderboard illustration introduces the Lead heading before its rows.
  Cascades use the 125 ms guide step. The CTA is inert and its pulse stays still
  off-slide and under Reduce Motion. These examples add no stops or sample data to
  the narration ([HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover),
  [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- Global Rankings and Compete's Leaderboards slide share one illustrative Lead card;
  Your Rank uses the same native [ranking rows](../../patterns/leaderboard-row.md)
  with the sample player's purple band. All three use the grouped
  [View All surface](../../patterns/view-all-cta.md), the 80 ms ranking cascade,
  and the shared pulse, which stays still under Reduce Motion or when the slide
  or scene is inactive. The rows and View All are decorative, not live scores or
  actions; the slide has one narration before the pager.
  [HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
  recommends focusing lessons on the actual experience;
  [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
  calls for making motion optional.
- The automatic Experimental Ranking Metrics lesson follows the same Settings gate as the
  Rank By menu; Settings can still replay the full guide. It illustrates the four choices
  without opening a menu or changing the selected metric. At standard heights, center the
  illustration in the space left by narration, allowing the rim to crop instead of crowding
  the pager. Short previews prioritize the first choices. Compete Hub alternates between
  sample rankings and Above You/Below You cards. Compete Rivals and Your Rivals alternate the group that changes;
  Per-Instrument Rivals changes two rows without replacing their headers. These previews
  use the shared ranking and rival rows, five-second swap clock and 80 ms entrance steps
  where applicable. Head-to-Head uses sample rank pairs and three bounded catalogue
  songs, redacts missing titles, and restaggers rows as its example category changes.
  The compact preview clips rows after the category heading, not the heading itself.
  These lessons do not query rivals or scores. Only narration and pager controls are
  interactive or spoken; Reduce Motion keeps each sample still
  ([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding),
  [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion),
  [HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)).
- Global Statistics, Per-Instrument Stats and Percentile Rankings use the same sample
  data in both renderers. The UIKit previews reuse the native Statistics tiles,
  instrument header and percentile table without linking to Songs or reading the
  selected player's scores. The instrument header and table enter before the narration
  with motion on. The SwiftUI grid and table replace their accessibility representation
  so their stat links cannot appear inside the narration; the UIKit examples likewise
  expose no sample actions
  ([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding),
  [HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)).
- Select Player Profile draws a decorative Select button for the shared example player;
  Drill Into Your Data draws the actual Statistics tiles with sample values and the
  production chevrons. They do not change selection or apply a filter. Both reuse the
  guide's two-second outline pulse, stationary when the slide or scene is inactive
  or Reduce Motion is on ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- Highest and Lowest Rank Breakdown centers four catalogue cards in the clipped preview.
  The artist and optional year accompany each title, and the gold sample percentage stays
  with its slot as two songs rotate on the shared catalogue clock. A missing catalogue
  redacts art and song text, not the illustrative percentages. The preview is decorative;
  only the narration reaches VoiceOver, and Reduce Motion keeps the rows still
  ([HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover),
  [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- The UIKit pager starts an incoming slide's fade as soon as its movement is committed,
  not after the movement settles. Only the settled slide is readable and recorded as seen.
  Reduce Motion displays slides fully drawn with no entrance
  ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)).
- Settings' Show buttons keep their blue fill through the guide sheet's native backdrop
  dimming, like the explicitly tinted SwiftUI buttons. The backdrop stays noninteractive
  until the guide closes ([HIG Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)).
  UIKit centers the compact painted capsule within a minimum 44 pt hit target and lets
  the fill grow with the label ([HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).
- Back keeps the guide's accent tint on both the horizontal navigation bar and the
  folded Duo rail. It stays a single native, named button, absent on the first
  lesson ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
- At standard text sizes the preview takes the space left by the narration and its bottom
  gap, bounded to 170–320 pt as in SwiftUI. On a short viewport the decorative insets yield
  to the narration before it needs to scroll. Compact height and accessibility sizes keep
  the 120 pt preview and scrollable narration
  ([HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
  For Songs and Shop row previews taller than the available space, crop the lower rows
  rather than cutting off both the first and last examples.
- Songs Sort and Filter, Player History Sort, and the two Suggestions Filter slides embed
  their native forms, cropped to the preview viewport without sheet navigation. The forms
  are inert and do not read or write the user's settings. The slide, not its preview rows,
  is the accessible element.
- The Songs Navigation slide uses a native tab controller with the same sample sections as
  SwiftUI, but no routes, accessory or exposed actions ([HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)).

## Architecture

- **Core (pure logic, `FestivalCore/`):**
  - `FirstRun.swift` — `FirstRunGateContext`, `FirstRunGate` (enum predicate, not a closure, so
    slide definitions stay `Equatable`/`Sendable` and unit-testable), `FirstRunSlide` (data only —
    no `render`; the UI layer maps `id` to a view), `FirstRunHashing` (djb2, ported bit-for-bit
    from the web's `contentHash`), `FirstRunSeenRecord`, and `FirstRunSlideEvaluator` (the pure
    `isUnseen`/`unseenSlides`/`gatePassingSlides`/`allSlides` functions).
  - `FirstRunSeenStore.swift` — bounded (`maxRecords = 500`, oldest-`seenAt`-first eviction),
    validated `UserDefaults` JSON persistence (`fst.firstRun.seen.v1`). A fully-corrupt or
    oversized (>256 KB) blob resets to empty, matching the web's `catch { return {} }`;
    individually malformed records (negative version, empty/oversized hash or id) are dropped
    while the rest of the store is kept — stricter than the web, never weaker.
  - `FirstRunCatalog.swift` — the full, hand-ported slide catalog for all 9 registered pages
    (`FirstRunPageKey`: `songs`, `songinfo`, `playerhistory`, `statistics`, `suggestions`,
    `leaderboards`, `compete`, `rivals`, `shop` — the same `pageKey` strings the web registers
    from `SettingsPage.tsx`). Only the mobile copy variant is ported for slides that differ by
    `isMobile` on the web (this lane targets iPhone only); each keeps the web's `contentKey` so a
    future desktop port would share seen-state.
  - `FestivalCoreTests/FirstRunTests.swift` — 36 tests covering hashing, `isUnseen` (missing
    record, version bump, content-hash change, `contentKey` sharing, a defensive lower-stored-
    version case), slide selection (gates, `ready`, the "only the new slide shows" scenario,
    `alwaysShow`, `gatePassingSlides`, `allSlides`), and the seen store (round-trip, corrupt data,
    oversized payload, per-record validation, bounding/eviction, `resetPage`/`resetAll`).
- **UI (`FestivalUI/Features/FirstRun/`):**
  - `FirstRunCenter` (`@Observable`, `@MainActor`) — one per session, reached via
    `session.firstRunCenter` (added the same weakly-keyed-registry way as
    `FestivalSession+Artwork.swift`'s `backgroundCoordinator`, so no edit to
    `FestivalSession.swift` itself was needed). Owns the `FirstRunSeenStore` and arbitrates the
    single `activeKey` ("one carousel at a time") via `claim`/`release`. Also resolves
    `FirstRunDebugMode` from `FST_DEBUG_FIRST_RUN` once at session start.
  - `.firstRun(page:session:)` (`FirstRunModifier.swift`) — the one seam every page needs.
    Evaluates gates from live `@AppStorage` settings + `session.selectedPlayer` on appear and on
    every relevant setting/profile change, presents a `.sheet` when unseen gate-passing slides
    exist and the shared slot can be claimed, and marks them seen (releasing the slot) in the
    sheet's `onDismiss` — so a swipe-to-dismiss is handled identically to tapping Skip/Done.
  - `FirstRunCarouselView.swift` — the paged carousel (operator batches 6–7): `TabView(.page)`
    with the system dots hidden and white `FirstRunPageDots` (current solid, others 35 %; one
    adjustable "Page, n of m" element); the system toolbar **Close** from the shared
    `FestivalModal` (`Button(role: .close)` glyph on iOS 26, issue #23; it replaced issue #4's
    text "Close", which itself replaced a hand-drawn ✕) beside an inline navigation title naming
    the page the guide explains (`FirstRunPageKey.guideTitle`, issue #24: the Settings row label,
    e.g. "Songs", "Score History"; all under 15 characters per HIG Toolbars), on launch and on a
    Settings replay alike. Controls follow Apple's onboarding layout (issue #25): a system
    toolbar **Back** chevron at the top leading edge (`fst.first-run.back`, label "Back", HIG
    Toolbars: "Leading: back/previous-document … controls, then the view title"; only after
    page one, never disabled); one large **Next/Done** drawn with the app's prominent action,
    `festivalProminentButton()` (`.borderedProminent` on `AccentText.prominentFill` with its
    Increase Contrast pair; `.controlSize(.large)`, ≈48 pt on screen; #626); then a
    full-width `.borderless` accent-tinted **Skip** beneath it (body text, ≥48 pt row; issue
    #380, see [Native controls and web motion](#native-controls-and-web-motion-issue-380)) until
    the last page. The Skip row stays reserved on the last page so Done doesn't move; a one-page
    guide shows only Done (`FirstRunControls` in `FestivalCore/FirstRunViewing.swift`:
    `showsBack`, `showsSkip`, `reservesSkipRow`, `minimumHeight`). iOS 26 draws the 86 % sheet
    about 0.96× scaled, so 48 pt layouts read ≈46 pt in XCUITest frames; the toolbar Back/Close
    report 34.6 pt frames but take system-expanded hit regions (near-miss taps at ±20 pt land).
    Embedded real sheets in demos (Sort/Filter) set `festivalModalPreview`, so `FestivalModal`
    renders only their content: a nested `NavigationStack` would otherwise merge its title
    ("Sort By") and a second, working Close into the guide's bar. Presented at an 86 % detent
    (`FirstRunSheetStyle`) so tapping the dimmed page above it, or swiping down, dismisses.
    VoiceOver focus is left to the system on open, so the navigation title is announced first
    (HIG VoiceOver: a screen's title is announced first); `@AccessibilityFocusState` then moves
    focus to each new slide on a page change. Accessibility test (#429,
    `FirstRunJourneyTests.testGuideTitleIsReadFirstAtLargestText`, Songs and Leaderboards guides,
    in `apple-ci`'s simulator journeys), each guide launched at the default size and at AX5: the
    title is a heading named by its page; across the whole app snapshot (not just the bar) the
    guide reads title → Close → first slide, and nothing of the page behind the sheet is in the
    tree except the system "Sheet Grabber" button, which UIKit orders ahead of every grabber
    sheet's content (sheet chrome, not body: `modal-shell` R2 holds); the title's ink grows
    ≥ 1.15× from default to AX5 (measured 1.22× "Leaderboards", 1.23× "Songs"; UIKit caps the
    inline bar title, `system-bar-title-size` in [accessibility](../../testing/apple/accessibility.md))
    and reads back whole at both sizes, wholly on screen beside a hittable Close; the AX5 bar
    audit, Dynamic Type included, is clean. The title is navigation-bar chrome a macOS-hosted view
    cannot reproduce (a hosted `NavigationStack` bridges no window title), so a simulator journey,
    not a hosted test, is its evidence. Animations skip under Reduce Motion. Each slide's
    title and description fade up after its demo cascade (`FirstRunMotion.textDelays`).
  - **Seen pages only**: the carousel records every page shown in a `FirstRunViewing` binding;
    the presenter's `onDismiss` marks only those seen (however it closed), so unviewed pages
    show next time (web new-info rule). Settings replays do the same after resetting the page.
  - `FirstRunDemoContent.swift` / `Demo/FirstRunSongsDemos.swift` — see the parity table below.
  - `FirstRunSettingsSection.swift` — the Settings "First Run Guides" section (web title): one
    "Show" row per `FirstRunPageKey` in the web's order (`settingsOrder`; Player History labelled
    "Score History" like the web's `history.title`), opening a carousel over `FirstRunSlideEvaluator.allSlides(...)` (gates and
    seen-state both ignored, matching `getAllSlides`), resetting that page's seen-state first
    (matching `useFirstRunReplay.open`'s `resetPage` call) and re-marking everything seen on
    dismiss. No "reset all" control — the web doesn't have one either.
- **Debug:** `FST_DEBUG_FIRST_RUN` — unset/anything else → `.off` in DEBUG (default, so other
  lanes' `ios_sim.py shot`/`drive` scripts aren't blocked by an unexpected sheet); `force` → shows
  every gate-passing slide on every page regardless of seen-state; `on` → real seen-state
  behavior in DEBUG. Release always behaves as `.normal` (real behavior), ignoring the env var
  entirely. No `FST_DEBUG_FIRST_RUN` handling existed anywhere on `master` at the time this landed
  (checked via `git log`/`grep` before starting), so there was nothing to reconcile with Lane X.

- **Slot sharing:** the launch What's New sheet claims `FirstRunCenter` slot `whats-new`, so a
  carousel and the changelog never present together ([whats-new](../whats-new/ios.md)).
- **Stars:** demos use the web's `star_white`/`star_gold` images (shared `Design/StarRating.swift`, wrapped by
  `Demo/FirstRunStar.swift`), never SF Symbol stars. Text is primary white; position is announced
  only through VoiceOver's `accessibilityValue` beside the page dots (no visible "Slide x of y").

## Seam edits (narrow, additive)

- `App/AppRouteDestination.swift` — `.firstRun(...)` appended to the 8 registered-page cases in
  the `switch` (`songDetail → .songInfo`, `playerHistory → .playerHistory`, `statistics`,
  `suggestions`, `leaderboards`, `compete`, `rivals`, `shop`); every other case (song leaderboards,
  player/band pages, rankings, licenses, …) is untouched — the web doesn't register those either.
- `App/FestivalRootView.swift` — the same 6 pages that are *also* tab roots (`songs`, `suggestions`,
  `leaderboards`, `compete`, `rivals`, `statistics`) get `.firstRun(...)` on their tab-root
  composition in `content(for:)` too, since reaching them as a tab never goes through
  `AppRouteDestination`. `FirstRunCenter.claim`/`release` make it safe for both the tab-root and a
  pushed-route instance of the same page to carry the modifier — only whichever is actually
  visible ever calls `onAppear`/succeeds at `claim` in practice.
- `App/FestivalSession+FirstRun.swift` — new file, following the established
  `FestivalSession+<Feature>.swift` convention; adds `session.firstRunCenter` without touching
  `FestivalSession.swift`.
- `Features/Settings/SettingsScreen.swift` — one line added to the section list:
  `FirstRunSettingsSection(session: session)`.

## Songs slide parity (9/9 — the app's real Songs UI, batch 7)

`Demo/FirstRunNativeSongsDemos.swift`. The presenter injects `\.firstRunSession`; demos show
three live catalogue songs with art (the cached keyless `/api/songs`, as the web demos switch to
catalogue songs once loaded). Demos are inert (no hit testing, hidden from VoiceOver; the slide's
title/description is the accessible content).

### Demo songs come from the catalogue (issue #26)

Every song-using demo (Songs, `statistics-top-songs`, `rivals-detail`,
`suggestions-category-card`, all four Shop demos) goes through
`FirstRunCatalogueSongs(count:source:content:)`; no demo ships invented titles.
- `FestivalCore.FirstRunDemoSongs.pick` ports the web's `useDemoSongs`/`useItemShopDemoSongs`:
  only songs with art; preferred IDs, then "Epic Games" artists, then the rest. Catalogue order
  replaces the web's shuffle so captures and tests stay deterministic (`FirstRunDemoSongsTests`).
- `.itemShop` prefers the session's already-loaded Shop songs only when Shop and catalogue
  observed publications match; demos never fetch the Shop.
- Loading, failure or no session: `FirstRunDemoSongs.placeholders` render as muted art tiles with
  `.redacted(.placeholder)` text (HIG Loading: "use placeholder text, graphics, or animations
  until content arrives"); the swap to live songs animates unless Reduce Motion is on
  (`FirstRunHostedTests.songDemosRenderPlaceholdersWithoutCatalogue`). Ranks and percentiles stay
  static `FirstRunDemoPool` numbers (Top Songs uses the web's `DEMO_PERCENTILES`).
- Song demos are decorative (HIG VoiceOver: "Exclude purely decorative images that convey no
  useful or actionable information"): placeholders and catalogue songs alike stay hidden, and
  the slide reads only "title. description", then dots, Next, Skip. Pinned per song demo in both
  states, at Large and AX5, by `FirstRunDemoSongsAccessibilityTests` (#401), and on iOS at AX5
  with `performAccessibilityAudit` by `FirstRunJourneyTests.testSongDemoSlideAccessibleAtLargestText`
  (in `apple-ci`'s simulator journeys).
- At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`) the slide takes the
  compact-height path: a 120 pt demo and the text in a `ScrollView` (#401: at AX5 the full layout
  cut the Song List description off after "Tap a song to see" under the dots). HIG Typography:
  "Keep text truncation to a minimum as font size increases." The combined slide keeps
  `.isStaticText` so the scroll path still reads as text.

| Slide id | Demo | Real UI used |
|---|---|---|
| `songs-song-list` | `FirstRunNativeSongListDemo` | `SongRowView` ×3 |
| `songs-sort` | `FirstRunNativeSortDemo` | `SongsSortSheet` (top, clipped) |
| `songs-navigation` | `FirstRunNativeNavigationDemo` | System `TabView` tab bar (Liquid Glass on 26) with the shell's `FestivalSection` titles and symbols; it sets `.tabViewStyle(.automatic)` because the carousel's `.page` style is inherited by nested tab views and would leave a blank pager with no tab bar, and on iOS 26.1 turns off the inherited page-tools bottom accessory and the tab-bar backdrop; each tab shows `BrandTokens.appBackground` inside `firstRunPreviewCard()` (fixed in #380) |
| `songs-filter` | `FirstRunNativeFilterDemo` | `SongsFilterSheet` (top, clipped) |
| `songs-icons` | `FirstRunNativeIconsDemo` | Row chrome + `SongInstrumentStatusChips` (`SongInstrumentBadge.demoPattern`) |
| `songs-metadata` | `FirstRunNativeMetadataDemo` | Row chrome + `SongMetadataFieldView` + `SongProfileMetadataPills` |
| `songs-shop-highlight` / `-new-in-shop` / `-leaving-tomorrow` | `FirstRunNativeShopDemo` | `SongRowView` with its Shop outline/badge |

Issue #380 moved the other pages' demos onto the app's real views where one exists (below);
the rest are still demo layouts built from the app's tokens.

## Native controls and web motion (issue #380)

Owner: "every single FRE needs a deep pass … to actually use platform UX that it's showing,
match web behaviors for animations, fades, infinite scrolls … and iOS needs a pass on
Next/Skip/Back". HIG Onboarding: "make onboarding fast, fun, and optional" and teach through the
app's own interface.

- **Rule: a demo shows the real control.** When the page has a reusable view for what the slide
  teaches, the demo embeds it inert (`firstRunInert()`), and sheets go in a
  `firstRunSheetPreview(height:)` frame. Never add a look-alike copy to `Demo/`. If a page's view
  can't be built without a session, extract a small public view from it (as with
  `ProfileIdentityButton`, `SongDetailShopGlyph`, `ScoreHistoryEntry.init(songId:…)` and
  `PlayerPercentileBucket.init(topPercent:count:)`, `SongPathsSelectorRow`).
- **Web motion lives in Core:**
  - `FestivalCore/FirstRunMotion.swift` holds the web timings. The cascade steps 125 ms, rows
    80 ms, Item Shop tiles 60 ms, Rivals detail 100 ms, with a 200 ms exit.
  - Each slide's `contentStaggerCount` (one per `FirstRunCatalog` slide id; `FirstRunMotionTests`
    checks coverage) delays the title by count × 125 ms and the description one step more.
  - `FirstRunAutoScroll` glides at 30 pt/s after 100 ms and wraps to the top. Its 36 pt fades
    show only on edges that hide cards.
  - Unit tests: `FirstRunMotionTests` (every catalogue slide has a count). The hosted tests
    `FirstRunDemoCoverageTests` cover the Item Shop row phases and the six scroll templates.
- **Replays like the web.** The web remounts a slide whenever it becomes visible, so cascades
  replay each time a page is shown, keyed on `\.firstRunSlideActive`. The still override
  (`FST_DEBUG_STILL_BACKGROUND`) shows everything at rest.
- **Reduce Motion** (system or app; HIG Accessibility: "reduce automatic and repetitive
  animation"):
  - no cascade and no title fade;
  - the infinite scroll holds at the top;
  - pulses hold at 0.7;
  - rotating demos never tick: they rest on their first state with no fade or transition.
  - Every First Run motion reads the one `@FirstRunReduceMotion` value (system or app).
    Never read `accessibilityReduceMotion` alone in `FirstRun/`.
- **Pulses** reuse the Item Shop row pulse (`ShopPulseLayer`, `ShopRowPulseBorder`; see
  [Apple architecture](../../platforms/apple/architecture.md)). Accent blue marks a CTA. Song rows and the
  Song Details action pulse in their own Item Shop tone.
- **Skip (agent decision, #380; the owner may override with `/choose`).**
  - Skip is now a full-width `.borderless` button: body text tinted `AccentText.blue`, ≥48 pt.
    It replaces the white plain text, which read as a web link.
  - Next/Done keep a prominent style (`festivalProminentButton()` since #626). HIG Buttons: "use a prominent style
    (accent-color background) for the most likely action" and "Distinguish the preferred choice
    by style, not size". This prominent primary with a tinted borderless secondary is the
    layout of Apple's own setup screens.
  - Back stays the system toolbar chevron (HIG Toolbars), and the white page dots stay (an
    operator decision).
  - Rejected: a bordered Skip, which competes with Next; and Skip in the toolbar, where Close
    already dismisses.
- **Next/Done use the app's prominent action (agent decision, #626; the owner may override with
  `/choose`).** The brand-blue `.glassProminent` Next failed `performAccessibilityAudit` contrast
  at AX5 on iOS 27 (iPhone and Duo folded), although its rendered fill measured about 4.95:1
  against the white label. Options: (A) `festivalProminentButton()`, the canonical prominent
  action (Choose Profile, [empty-error-states](../../patterns/empty-error-states.md) R5): white on
  `AccentText.prominentFill` (5.2:1) and a dark label on the white Increase Contrast tint;
  (B) keep `.glassProminent` with a darker tint; (C) keep the glass and accept the flag on a
  rendered measurement. Chose A: it passes the audit outright (verified on iOS 27 at AX5, iPhone
  and Duo folded), adds the Increase Contrast variant the glass lacked, and reuses one component
  instead of a First Run-only style; B is unproven against the audit's glass reading and C
  would keep a flagged control. HIG Buttons (should): "use a prominent style (accent-color
  background) for the most likely action"; HIG Accessibility (should): text at least 4.5:1, and
  "If not met by default, provide it when Increase Contrast is on"; HIG Materials: "Don't use
  Liquid Glass in the content layer". This narrows [Liquid Glass](../../design/apple/liquid-glass.md)'s
  "primary buttons in content" row for First Run.
- **Accessibility (#380, backfilled by #498).** HIG VoiceOver: "Exclude purely decorative images
  that convey no useful or actionable information".
  - Hosted (`FirstRunNativeDemosAccessibilityTests`, the shared SwiftUI of every Apple platform):
    - All 42 catalogue demos are checked, active with motion on and past their entrance. None
      exposes an element through `accessibilityChildren`.
    - The 10 real-control slides (Sort, Navigation, Filter, View All, Paths, Item Shop button,
      Player History sort, Select Player, both Suggestions filters) each read as one
      `AXStaticText` "title. description" with no custom actions. They are read before the dots,
      Next and Skip, with nothing else reachable.
    - System and app Reduce Motion show the title and description at rest from the first frame;
      with motion allowed they fade in. Reduce Motion also holds the infinite scroll still.
    - Reduce Transparency, Less Transparency, Increase Contrast and More Contrast each remove
      its bottom fade while leaving the top unchanged ([scroll-edge](../../patterns/scroll-edge.md) R7).
    - Skip's `AccentText.blue` keeps ≥ 4.5:1 on the sheet.
  - iPhone and the simulated folded Duo at AX5
    (`FirstRunJourneyTests/testSongsGuideRealControlDemosAccessibleAtLargestText[DuoFolded]`,
    `apple-ci` journeys). The test walks all six Songs pages:
    - each slide's exact name;
    - no button, tab, toggle, cell or text from the real Sort sheet, tab bar or rows inside the
      slide;
    - reading order slide → dots → Next/Done → Skip;
    - named 44 pt Next, Done and Skip, and Back from page two;
    - `performAccessibilityAudit` on Sort, Navigation and the last page (clipped text, hit
      regions, descriptions, element detection, contrast), with no issue accepted.
  - **Rule: a real control's UIKit views need UIKit hiding.** `accessibilityHidden` is a SwiftUI
    modifier and never reaches a separate UIKit host. Each `Form`/`List` row is its own SwiftUI
    host in a collection-view cell, and a `TabView` is a `UITabBarController`. On iPhone the Sort
    Songs slide read the sheet's cells and its Title, Artist, Year and Duration buttons, and the
    Navigation slide read its tab bar and five tabs (found by #498, shipped since #380). On iOS,
    `firstRunInert()` therefore adds `FirstRunPlatformAccessibilityHider`, a background probe
    that marks every UIKit view inside the preview's frame `accessibilityElementsHidden`. It
    never marks its own ancestors (the carousel pager, the slide's AX5 scroll view). Every demo
    that shows a real control uses `firstRunInert()`, never a bare `accessibilityHidden`.
    Hosted macOS tests can't see this leak; only the XCUITest journey does.
  - **Rule:** `firstRunInert()` collapses the preview (`.accessibilityElement(children: .ignore)`)
    before `accessibilityHidden`. On macOS a menu-style `Picker`'s title label escaped
    `accessibilityHidden` alone: the Paths demo read "Instrument", "Difficulty" and "View"
    (found by #498; the carousel slide's combine had absorbed them). Test a demo's exposure with
    an `accessibilityChildren` walk: the Navigation demo's macOS `NSTabView` is an AppKit
    subview the host never lists, so `macAccessibilityTree`'s subview walk reports a tab group
    that VoiceOver doesn't reach.

### FREs reviewed (#380)

One shared implementation serves every Apple form factor. Every slide was checked against the web demo and its page's real view. Rotating slides hold still under system or app Reduce Motion.

| Page | Slides | Outcome |
|---|---|---|
| Songs (9) | song-list, sort, navigation, filter, icons, metadata, shop-highlight, new-in-shop, leaving-tomorrow | Already the real Songs UI (batch 7). The text cascade was added; Item Shop rows use the real pulse |
| Song Info (8) | chart, bar-select, view-all, top-scores, paths, shop-button, new-in-shop, leaving-tomorrow | Real score rows, `PurpleActionLabel`, the Paths sheet's real menus (`SongPathsSelectorRow`) and the real Item Shop action; web cascade |
| Player History (2) | score-list, sort | Real rows and the real sort sheet |
| Statistics (6) | select-profile, drill-down, overview, instrument-breakdown, percentiles, top-songs | Real Select Player button, section header and percentile table; the stat grids already use the page's cards |
| Suggestions (4) | category-card, global-filter, instrument-filter, infinite-scroll | Real filter sheet; the infinite scroll is ported |
| Leaderboards (3) | overview, experimental-metrics, your-rank | Web cascade (80 ms rows) |
| Compete (3) | hub, leaderboards, rivals | Web cascade |
| Rivals (3) | overview, instruments, detail | Real instrument headers; web cascade (80/100 ms) |
| Item Shop (4) | overview, highlighting, new-items, leaving-tomorrow | Real Songs rows with the Item Shop pulse; 60 ms tile cascade |

What's New has no demos, so it's not applicable. Android and Windows follow in their own
platform notes.

## Other pages (31 slides) — live native demos (Lane D2, 2026-09-28)

Every remaining registered slide across Song Info (8), Player History (2), Statistics (6),
Suggestions (4), Leaderboards (3), Compete (3), Rivals (3) and Item Shop (4, `shop-views`
intentionally omitted — this lane's Shop screen has no grid/list view toggle yet) now renders a
live native mini-demo, ported from `pages/<page>/firstRun/demo/*.tsx` and the shared
`firstRun/demoData.ts`. All 42 catalog slides (9 Songs + 33 registered here) now resolve to a
live demo; `FirstRunDemoContent.hasLiveDemo(id:)` is unit-tested
(`FirstRunDemoCoverageTests.everyCatalogSlideHasALiveDemo`) against the full catalog so a future
slide added without a demo fails the build instead of silently falling back to
`FirstRunStaticIllustration`.

Shared building blocks live in `Features/FirstRun/Demo/`:
- `FirstRunDemoPool.swift` — hand-picked static sample numbers (rankings, rivals, score
  history, percentiles, rival rank/score comparisons), mirroring the shape of the web's
  `demoData.ts`. It holds no songs: song-using demos read the catalogue (see "Demo songs come
  from the catalogue" above).
- `FirstRunDemoSupport.swift` — `firstRunPulse(_:)` (the web's `pulseWrap`: a 2 pt border
  tracing the surface, opacity 0 → 0.7 → 0 over 2 s, drawn by the Item Shop row pulse's
  `ShopPulseLayer`; held at 0.7 under Reduce Motion and still on any slide but the visible one,
  via `\.firstRunSlideActive` and `FirstRunPulsePolicy`, because the paged `TabView` keeps
  neighbours alive; the sheet also pauses the backdrop, see [artwork background](../artwork-background/ios.md#power-and-frame-budget-issue-28)),
  `firstRunStagger(_:interval:)` (the web's cascading `FadeIn`, replayed each time the slide
  becomes the visible page and faded out over 0.2 s as it leaves; content appears at rest under
  Reduce Motion) and `firstRunFadeIn(delay:)` for slide text, plus shared row views
  (`FirstRunRankRow`, `FirstRunRivalRow`, `FirstRunViewAllRow`, `FirstRunInstrumentHeader`,
  `FirstRunSongArt`, which draws a real song's shared-cache artwork or a muted placeholder tile;
  `FirstRunViewAllRow` draws the real buttons' `PurpleActionSurface` and each demo passes it as
  its group card's `action:`, so it ends the card inside it like the real pages,
  [view-all-cta](../../patterns/view-all-cta.md) R1, #382)
  and `firstRunAccuracyTint(_:isFullCombo:)`, an accuracy-to-color
  ramp approximating the web's `accuracyColor` gradient.

`firstRunPulse`/`firstRunStagger` are pure SwiftUI (`withAnimation`/`repeatForever`), not
`Timer`/Combine. `firstRunStagger` uses the web `FadeIn` timing (0.4 s ease-out, 125 ms per row,
12 pt rise; `FirstRunDemoTiming`).

### Data-swap rotation (issue #27)

The web demos rotate to new data on a timer (`useSlideRotation`/`useRowSwaps`, CSS `ease` fades).
Before #27 iOS showed one static state per demo; now each rotating demo swaps like the web:
- **Core:** `FestivalCore/FirstRunDemoRotation.swift` holds the web timing (`FirstRunDemoTiming`: 5 s
  interval, 400 ms fade out → swap while hidden → 400 ms fade in), `FirstRunDemoRotation.swapCount`/
  `swapIndices` (web: 1 row per tick for up to 3 rows, 2 for 4–6, else 3, chosen at random; seeded SplitMix64 here for
  determinism), `FirstRunRowRotation` (swap rows to unused pool songs, never showing a duplicate),
  `FirstRunWindowRotation` (fixed-size windows over a pool) and `FirstRunDemoScorePattern` (the
  web's per-title `hashString` → FC/scored/none chips). Unit tests: `FirstRunDemoRotationTests`.
- **Driver:** `Demo/FirstRunDemoRotationViews.swift`. `FirstRunCarouselView` sets
  `\.firstRunDemoActive` only for the visible page while the scene is `.active`, so the
  `TabView(.page)` slides mounted off-screen run no timer (the reason rotation was skipped before).
  `.firstRunDemoTicker` is a `task(id:)` sleep loop; it also stops in Low Data Mode for demos that
  load artwork and under `FST_DEBUG_STILL_BACKGROUND`. `FirstRunDemoSwap.run` performs fade out →
  update without animation → fade in; `.firstRunSwapRow` hides the fading slots (opacity 0 plus the
  web's per-demo rise). Rows use positional identity so the same view fades instead of being
  replaced. Swapped-in artwork is prefetched into the shared bounded cache during the fade-out.
- **Reduce Motion** (system or app, `@FirstRunReduceMotion`; HIG Accessibility: "reduce
  automatic and repetitive animation"): the ticker stops (`FirstRunDemoTickerPolicy`), so each
  demo rests on its first state with no fade, rise or transition (#380, load-transition R6).
- Hosted tests: `FirstRunDemoRotationUITests` (swap order, ticker policy, cancellation
  completes, web pools/templates; an active bar-select demo advances while an inactive one
  stays still, and system or app Reduce Motion holds an active one still past its interval).
- Accessibility (#402): `FirstRunDemoRotationAccessibilityTests` hosts all 12 rotating demos
  active with motion on, samples through a swap and requires the picture to change while nothing
  becomes reachable (no element, song, placeholder or rival text). System or app Reduce Motion holds
  every one of them still. The Statistics carousel slide reads the same before and after a swap at
  Large and AX5: the same name, role, order and frames, and the targets still meet their minimum sizes.
  On iPhone at AX5, `FirstRunJourneyTests.testSongDemoRotationKeepsSlideAccessibleAtLargestText`
  (`FST_DEBUG_STILL_BACKGROUND=0`, an `apple-ci` journey) waits past a live swap and runs the AX5
  checks and `performAccessibilityAudit` again. **Rule:** a swapped-in tile's loading spinner
  (`ArtworkTile` → `FestivalLoadingView`) stays out of the accessibility children because the
  demo is `accessibilityHidden`. On macOS, `macAccessibilityTree` still lists the
  `NSProgressIndicator` behind it, because that walk also descends AppKit subviews, so test what
  VoiceOver reaches with an `accessibilityChildren` walk (as `ReloadGateAccessibilityTests.reachable`
  does).

| Slide | Rotation (web source) |
|---|---|
| `songs-song-list` | 1 row per 5 s from a 24-song pool (`SongListDemo`) |
| `songs-icons` | 2 rows, chips follow the per-title hash pattern (`SongIconsDemo`) |
| `songs-metadata` | 1 row; pills from the web `META_DATA` record picked by title hash (`MetadataDemo`) |
| `statistics-top-songs` | 4 rows, 2 per tick (`TopSongsDemo`) |
| `songinfo-bar-select` | Selection starts at bar 0 and moves every 2.5 s; detail card fades 300 ms (`BarSelectDemo`) |
| `suggestions-category-card` | The web's 4 templates in order, whole card fades with an 8 pt rise (`CategoryCardDemo`) |
| `leaderboards-experimental-metrics` | Selected metric advances every 5 s, no fade (`ExperimentalMetricsDemo`) |
| `compete-hub` | Alternates leaderboard and rivals layouts, 6 pt rise (`CompeteHubDemo`) |
| `compete-rivals` / `rivals-overview` | Above, then Below group swaps to the next window of the web's 6-rival pools, 4 pt rise |
| `rivals-instruments` | 6 rival slots, 2 per tick, each walking its own above/below pool |
| `rivals-detail` | Whole card fades; the category advances through the web's 6 and rows re-stagger |

The infinite-scroll demo's auto-scroll is ported in #380 (see below); Shop demos have no
rotation on the web either.

| Slide id | Live demo | Notes |
|---|---|---|
| `songinfo-chart` | `FirstRunSongInfoChartDemo` | Swift Charts `BarMark` (accuracy, gold when FC) with score annotated per bar |
| `songinfo-bar-select` | `FirstRunSongInfoBarSelectDemo` | Same chart; the selection stroke and detail card cycle bars like the web (see rotation table) |
| `songinfo-view-all` | `FirstRunSongInfoViewAllDemo` | Real `ScoreHistoryListRow`s (last one faded) + pulsing `PurpleActionLabel` "View All Scores" |
| `songinfo-top-scores` | `FirstRunSongInfoTopScoresDemo` | Instrument header + top leaderboard rows + pulsing "View full leaderboard" |
| `songinfo-paths` | `FirstRunSongInfoPathsDemo` | The Paths sheet's real Instrument/Difficulty/View menus (`SongPathsSelectorRow`, inert) below a still path-area placeholder (no network image fetch); selectors fade in first, as on the web |
| `songinfo-shop-button` | `FirstRunSongInfoShopPillDemo(tone: .shop)` | Song header card with the real Song Details Item Shop action (`SongDetailShopActionStyle`: breathing bag, or the titled `festivalCardCapsule` on a vertical section bar — a demo replica is a custom control, so never shipping glass (surface-materials `apple-glass-consumers`)); green |
| `songinfo-new-in-shop` | `FirstRunSongInfoShopPillDemo(tone: .new)` | Same, gold |
| `songinfo-leaving-tomorrow` | `FirstRunSongInfoShopPillDemo(tone: .leaving)` | Same, red |
| `playerhistory-score-list` | `FirstRunPlayerHistoryScoreListDemo` | Real `ScoreHistoryListRow`s, personal best highlighted |
| `playerhistory-sort` | `FirstRunPlayerHistorySortDemo` | The real `PlayerHistorySortSheet` in a sheet preview |
| `statistics-select-profile` | `FirstRunStatsSelectProfileDemo` | Player card with the real Profile `ProfileIdentityButton` (Select Player), pulsing |
| `statistics-drill-down` | `FirstRunStatsDrillDownDemo` | 2-col stat grid; drillable cards pulse |
| `statistics-overview` | `FirstRunStatsOverviewDemo` | 2-col global summary stat grid |
| `statistics-instrument-breakdown` | `FirstRunStatsInstrumentBreakdownDemo` | Real `InstrumentSectionHeader` + 2-col stat grid |
| `statistics-percentiles` | `FirstRunStatsPercentilesDemo` | The real `PlayerPercentileTableCard` |
| `statistics-top-songs` | `FirstRunStatsTopSongsDemo` | 4 catalogue song rows (art, artist · year) with the web's demo percentile badges |
| `suggestions-category-card` | `FirstRunSuggestionsCategoryCardDemo` | Rotating themed card of 2 catalogue songs: the real `SuggestionCategoryCardView` with a session, else a redacted approximation |
| `suggestions-global-filter` | `FirstRunSuggestionsGlobalFilterDemo` | The real `SuggestionsFilterSheet` in a sheet preview |
| `suggestions-instrument-filter` | `FirstRunSuggestionsInstrumentFilterDemo` | The same sheet with its per-instrument sections |
| `suggestions-infinite-scroll` | `FirstRunSuggestionsInfiniteScrollDemo` | The web's 6 category cards glide up at 30 pt/s and loop, with 36 pt edge fades only on edges hiding cards (`FirstRunAutoScroll`); still under Reduce Motion |
| `leaderboards-overview` | `FirstRunLeaderboardsOverviewDemo` | Instrument header + top rankings |
| `leaderboards-experimental-metrics` | `FirstRunLeaderboardsExperimentalMetricsDemo` | Metric radio list with hints |
| `leaderboards-your-rank` | `FirstRunLeaderboardsYourRankDemo` | Rank neighborhood, player row highlighted, pulsing "View all rankings" |
| `compete-hub` | `FirstRunCompeteHubDemo` | Alternates compact rankings and rivals above/below, like the web |
| `compete-leaderboards` | `FirstRunCompeteLeaderboardsDemo` | Reuses `FirstRunLeaderboardsOverviewDemo` |
| `compete-rivals` | `FirstRunCompeteRivalsDemo` | Above/Below rival rows (2 each), rotating |
| `rivals-overview` | `FirstRunRivalsOverviewDemo` | Above/Below rival rows (3 each), staggered and rotating |
| `rivals-instruments` | `FirstRunRivalsInstrumentsDemo` | Per-instrument rival sections under the real `InstrumentSectionHeader`, rotating 2 slots per tick |
| `rivals-detail` | `FirstRunRivalsDetailDemo` | Category card ("Closest Battles" first) of 3 catalogue songs with demo rank comparisons; cycles the web's 6 categories |
| `shop-overview` | `FirstRunShopOverviewDemo` | 3-column grid of 6 Item Shop/catalogue song art tiles |
| `shop-highlighting` | `FirstRunShopHighlightingDemo` | Real Songs rows (`SongRowView`) alternate the green Item Shop pulse and none |
| `shop-new-items` | `FirstRunShopNewItemsDemo` | Real Songs rows cycle gold/green/none by index (`FirstRunShopRowPhase`, no timer) |
| `shop-leaving-tomorrow` | `FirstRunShopLeavingTomorrowDemo` | Real Songs rows cycle red/green/none by index |

Simplified vs. the web on every demo: song-using demos show catalogue songs and their art, but
ranks, scores and percentiles are static demo numbers rather than the player's session data
(matching the web's own first-run pools), and there are no interactive taps (the carousel demos are
inert previews, same as Songs').

## Known gaps / follow-ups

- `shop-views` slide omitted pending the Shop grid/list view toggle (add it back to
  `FirstRunCatalog.shop` once that toggle ships).
- `ready` is always `true`: `FestivalSession` resolves the selected-player identity synchronously
  from storage at init, so there's no async gap where gates could evaluate against stale data on
  this platform. Revisit if a future async gate dependency is added.
- XCUITest: `FirstRunJourneyTests.swift` (Next first with Skip beneath and Back in the bar
  before the title (`testNextFirstThenBackAppears`), Done on the last page, ≥44 pt Next/Skip
  frames and near-miss taps on Back/Next/Skip/Close read as buttons
  (`testControlsAcceptNearMissesAndReadAsButtons`), one Close and the guide title on every
  slide (`testEmbeddedSheetDemosKeepOneCloseAndTheGuideTitle`), native navigation-bar
  Close labelled "Close" (`testCloseIsNativeToolbarButton`), the page's navigation title on launch
  and on a Settings replay (`testGuideShowsPageTitleInNavigationBar`), swipe-down and tap-outside dismissal, viewed-pages-only across a relaunch; needs `mock_service.py --port 8765`).
  Tap-outside must land below the status bar (a status-bar tap is scroll-to-top).
- `contracts/product.json` has no `first-run` control entry yet (orchestrator-owned file, not
  edited by this lane) — `check_docs.py` reports the same pending "topic not in contracts"
  warning that `songs-section-index` already has on `master`.
