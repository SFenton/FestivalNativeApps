# Songs Filter (`fst.songs.filter`) - partial iPhone implementation

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:587-618,1122-1136`,
`FortniteFestivalWeb/src/pages/songs/modals/FilterModal.tsx:155-179,305-321`,
`FortniteFestivalWeb/src/hooks/data/useFilteredSongs.ts:103-140`, and
`FortniteFestivalWeb/src/utils/songSettings.ts:92-124,155-174`.
These files are pinned in `contracts/source-snapshot.json`; the sibling
source checkout remains independently dirty. The source's mobile
Filter action requires loaded player data or a selected band.

**Implemented slice:** A selected player with available scores gets a
native toolbar Filter action. Its system sheet currently stages only
the source's two public Shop toggles, **In Shop** and **Leaving
Tomorrow**. They are independent; Leaving Tomorrow implies current
membership, so selecting both retains leaving offers. Search and the
existing chart filter run before Shop filtering; Sort runs afterward.
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
response was pinned. Never synthesize empty membership from HTTP 503,
send selected-profile headers or request a privileged key.
Native entrypoints are `apple/Sources/FestivalCore/SongShopFilter.swift`,
`apple/Sources/FestivalUI/SongScreens.swift` and
`apple/Sources/FestivalUI/SongsShopFilterSheet.swift`; the iOS Debug
app resets fixture-only preferences in `apple/Apps/iOS/FestivalMobileApp.swift`.

| State / action | Native rule and evidence still needed |
|---|---|
| Anonymous / selected | An anonymous user has no Filter action by default, matching the PWA mobile dock. A selected player with available scores can **edit** filters; saved public Shop filtering continues while that player's scores load, sync or fail when Shop/catalogue generations still match. The PWA clears filters on confirmed deselect or player/band type change but preserves player-to-player switches. Native deliberately retains the public Shop choice through deselect, offers Reset even anonymously and reapplies it after explicit reselection; this is a tested parity deviation, not the PWA's behavior. Band mode is blocked pending a mutation-free service policy. |
| Default / draft / discard | Both toggles start off. Changes stay in the sheet until Apply; Cancel asks to continue or discard only for a changed draft. A pinned footer stays reachable; reset clears the *draft* and still requires Apply. |
| Shop data | A visible, same-generation validated feed enables toggles, including a validated empty feed. Hidden Shop, no selected identity, a missing/failed cold feed or a catalogue/Shop publication mismatch pauses saved choices with an explicit notice and shows retained rows without new Shop badges or grouping. Score-loading alone does **not** pause effective public Shop membership, although editing stays disabled until scores are available. A retained validated warm feed may keep filtering while a separate refresh error is disclosed. When Shop is hidden, the PWA **omits** its Shop controls; native deliberately retains **disabled** toggles and Reset to make saved choices clearable. |
| Apply / relaunch | Applied choices survive app relaunch; actual row membership changes, not just button tint. Leaving Tomorrow uses the offer flag, not the New highlight. A true empty validated feed shows No Results for active Shop filters; an error never masquerades as empty. |
| Accessibility | Name and announce Filter, each toggle, Reset, Cancel and Apply. Check the visible row and notice after changing Shop, profile and Settings, large-text footer reachability, focus return and an unwaived audit per supported posture. |

IDs: `fst.songs.filter{,.in-shop,.leaving,.reset,.cancel,.apply}` and
`fst.songs.filter-paused`. Source phone WebKit fixtures show a long
bottom sheet with score, FC, season, percentile, stars, intensity,
band and Shop sections. Native iPhone 26.5 deliberately uses a
full-height system sheet with **only Shop controls**; the source
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
phone case proves the source Filter is absent anonymously and
that selected In Shop and Leaving Tomorrow change the same
two-song synthetic list. Full score/instrument/band filters,
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
