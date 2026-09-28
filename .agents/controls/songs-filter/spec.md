# Songs Filter (`fst.songs.filter`) - partial iPhone implementation

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:587-618,1122-1136`,
`FortniteFestivalWeb/src/pages/songs/modals/FilterModal.tsx:77-132,155-270,305-321`,
`FortniteFestivalWeb/src/hooks/data/useFilteredSongs.ts:103-182`, and
`FortniteFestivalWeb/src/utils/songSettings.ts:92-124,155-174`.
These files are pinned in `contracts/source-snapshot.json`; the sibling
source checkout remains independently dirty. The source's mobile
Filter action requires loaded player data or a selected band.

**Implemented iPhone slices:** A selected player with available scores
gets a native toolbar Filter action, including when Shop is hidden.
The source's two public Shop toggles, **In Shop** and **Leaving
Tomorrow**, remain independent; Leaving Tomorrow implies current
membership, so selecting both retains leaving offers. The same
sheet now stages four **global** score/FC conditions plus four
conditions under each Settings-visible instrument. Search and the
existing chart filter run before Shop filtering, then selected-player
score filtering; Sort runs afterward.
`SongShopFilter.filtered` requires validated offers for either active
toggle, distinguishes a genuinely empty feed from absent/failed data,
and preserves the input row order. `FestivalSession.shopOffersById`
comes only from the validated public Shop response. One
`SongShopPublicationPolicy` decision requires the loaded catalogue,
validated Shop and current session to share their **observed**
generation before Filter, Shop Sort/grouping or Songs-row Shop
badges use those offers. A failed refresh may retain older Songs:
keep them visible with explicit paused notices, without newer Shop
membership or badges. An observed ID is not proof that a headerless
response was pinned. The selected-player score index now has its **own**
observation and paused state for the same old-Songs/new-profile failure;
it does not control public Shop membership or Filter editing. Never
synthesize empty membership from HTTP 503,
send selected-profile headers or request a privileged key.
Native entrypoints are `apple/Sources/FestivalCore/{SongShopFilter,SongPlayerScoreFilter}.swift`,
`apple/Sources/FestivalUI/SongScreens.swift` and
`apple/Sources/FestivalUI/SongsFilterSheet.swift`; the iOS Debug
app resets fixture-only preferences in `apple/Apps/iOS/FestivalMobileApp.swift`.

| State / action | Native rule and evidence still needed |
|---|---|
| Anonymous / selected | An anonymous user has no Filter action by default, matching the PWA mobile dock. A selected player with available scores can **edit** public Shop and validated score filters. Saved public Shop filtering continues while that player's scores load, sync or fail when Shop/catalogue generations match. The PWA clears all filters on confirmed deselect but preserves player-to-player switches. Native now clears **only player-score predicates** on deselect; it deliberately retains the public Shop choice, offers Reset anonymously and reapplies Shop only after explicit reselection. Band mode remains blocked pending a mutation-free service policy. |
| Default / draft / discard | Shop and score choices start off. Changes stay in the sheet until Apply; Cancel asks to continue or discard only for a changed draft. A pinned footer remains reachable; Reset clears the *draft* of all available filters and still requires Apply. A saved score predicate starts its disclosure expanded; an empty score draft starts collapsed. |
| Player score and FC | `SongPlayerScoreFilter` uses the existing one-time per-song profile index, never another GET or a raw cold-launch cache. Four independent source checks per chart combine **AND within one chart, OR across active charted instruments**; global toggles set/clear only visible charts. Hidden choices stay saved but inactive and are disclosed; applying a draft removes hidden choices like source sanitization. FC follows the explicit score flag even for a contradictory zero-score/FC tuple; the separate native status chip still flags that inconsistency. A valid 200 empty score index permits Missing Scores on charted songs natively, unlike the source's `allScoreMap.size > 0` gate: a documented correctness deviation. |
| Score provenance / invalid settings | Selected score checks apply only when the catalogue, proven selected-player response and native session share the current **observed** publication. Loading, 202, HTTP failure, a changed publication or Settings' still-unsupported Filter Invalid Scores substitution pause score checks with a visible notice; an absent/failed index never masquerades as zero scores. Public Shop checks remain independent. |
| Shop data | A visible, same-generation validated feed enables toggles, including a validated empty feed. Hidden Shop, no selected identity, a missing/failed cold feed or a catalogue/Shop publication mismatch pauses saved choices with an explicit notice and shows retained rows without new Shop badges or grouping. Score-loading alone does **not** pause effective public Shop membership, although editing stays disabled until scores are available. A retained validated warm feed may keep filtering while a separate refresh error is disclosed. When Shop is hidden, the PWA **omits** its Shop controls; native deliberately retains **disabled** toggles and Reset to make saved choices clearable. |
| Apply / relaunch | Applied Shop and player-score choices survive app relaunch; score bytes do **not**. The four chart sets persist as bounded, typed, deterministic service-ID JSON; corrupt preferences block the Songs success view until the user explicitly resets only those score filters. Actual row membership changes, not just button tint. A true empty validated Shop feed shows No Results for active Shop checks; an error never masquerades as empty. |
| Accessibility | Name and announce Filter, its score disclosure, four global toggles, four toggles for each visible chart, Shop choices, Reset, Cancel and Apply. Only the disclosure *label* has the chart ID: putting an ID on its whole SwiftUI `DisclosureGroup` replaced all nested toggle IDs on iOS 26. The Form has its own ID for scrolling; an opaque native iOS title and Form are **separate vertical siblings**, so XL text scrolls in a clipped viewport rather than behind Liquid Glass. Check each state/posture and real visible row after changing Shop, player, Settings, chart, and text size; full VoiceOver/focus proof is still pending. |

IDs: `fst.songs.filter{,.form,.title,.in-shop,.leaving,.reset,.cancel,.apply}`,
`fst.songs.filter.score-sections`, `fst.songs.filter.score.{global,instrument,chart}.*`,
`fst.songs.{filter-paused,score-filter-paused,score-filter-hidden}`,
`fst.songs.filter-{invalid,reset-invalid}` and `fst.songs.filter.save-error`
are registered in `contracts/product.json`. Source phone WebKit fixtures show a long
bottom sheet with score, FC, season, percentile, stars, intensity,
band and Shop sections. Native iPhone 26.5 deliberately uses a
full-height system sheet with Shop and expandable score/FC controls; the source
still includes **season, percentile, stars, difficulty, score threshold,
selected instrument and band/member** Filter sections not in this sheet.
The source
adds Suggestions, Compete and Statistics tabs for a selected player
while native still has three root tabs. Do not call matched Shop
row changes modal, navigation or pixel parity.

`shopSongFiltersMatchSourceAndRejectAbsentFeed` tests positive,
empty and denied membership policy.
`shopPublicationMatchPreservesValidatedEmptyWithoutMixingGenerations`
and `songsPauseShopDerivedRowsAcrossFailedPublicationRollover`
exercise a scripted generation 7→8 transition: newer Shop and
profile reads succeed, new Songs returns HTTP 503, older Songs
remain in title order without new Shop-colored card borders.
A separate rendered state keeps the Leaving row filtered while
selected-player scores are still loading. The dedicated
**pinned** `--rollover-on-command --mismatched-shop-rollover`
fixture runs on fresh runner-owned 8777 (iPhone) or deferred
8778 (iPad): after the one-shot command, Shop exposes only
Fixture Pulse and the selected player remains readable at
publication 8, while every new Songs read (including old
ETags) fails HTTP 503. Numeric-only
`/__fixture__/publication-join-reads` proves the three
independent request generations. The exact iPhone 26.5
device test passes **1/1**, and a four-case iPhone Join/
AX5 Retry/warm-offline/Shop error matrix passes **4/4**.
The old Orbit and Pulse rows are each scrolled fully above
the system tab, with no newer Shop badge IDs or grouped
headers and explicit paused Sort/Filter notices; these
private screenshots are not pixel-parity proof. The iPad
listener is configured but its simulator has not run.
Native
AppKit-hosted snapshots also paint seven sheet states and
selected-player loaded/empty/failed/paused Song screens. The iPhone
`testSelectedShopFilterDraftApplyDiscardAndRelaunch` and
`testSelectedShopFilterPausesAndRecoversAcrossShopStates` pass their
named fixture journeys. The loaded default and AX5 Filter sheets
pass unwaived iPhone 26.5 `.all` audits; at AX5 the automation
scrolls the **Form itself** until Reset is completely above the
pinned footer, measures real Apply glyph growth >1.35x and
rendered text ≥4.5:1, then applies the selected filter. The
shared Form-owned Reset helper also preserved anonymous Sort
and Shop Sort in a selected iPhone **3/3** regression. A WebKit
phone cases prove the source Filter is absent anonymously,
In Shop/Leaving Tomorrow change the same two-song list, and
**Has Drums Scores** changes that list to Pulse only before Reset
restores both. Three Core score-filter cases cover OR/AND, empty,
absent, zero-FC, visibility, globals and bounded preference decoding.
Actual normal/AX5 iPhone score journeys separately pass with
draft/discard, row changes, cold retention, Settings invalid-score/
chart-hide pause, clear-on-deselect and unwaived loaded score-sheet
audits; a scripted hosted old-Songs/new-profile/Shop/HTTP503
case also pauses both kinds of filters. The full seven-case
source-frozen iPhone 26.5 regression now passes **7/7**
with the old Shop draft/hide/error/AX5 and pinned publication
journeys. The separately measured seven-case `FestivalUI`/app
subset is only **2630/4992 unique lines (52.68%, below 90%)**,
not an iPhone line-category pass. The full SwiftPM host categories
pass **2000/2087 logic (95.83%)** and **9430/10415 UX (90.54%)**,
and iPhone Release builds; host coverage is not native device-line
or complete control-state evidence.
Remaining season/percentile/stars/threshold/intensity/band filters,
Shop WebSocket updates, rapid transitions, other AX5 states,
older iOS, Duo poses, iPadOS/macOS GUI and representative scroll
performance remain pending. This control and the Songs route
are **not certified**. Public account search/ranking currently
hits the deployed edge access-denied boundary; selected-player
device evidence here is fixture-backed, not proof of production
account access. A saved Shop sort combined with warm-offline
Shop failure still has an **unidentified contrast** finding
on the full Songs `.all` audit; the isolated Title-sort
warm-offline test passes only with its documented, exact
Shop Retry issue handler. Do not extend that exception to
the unnamed issue.
