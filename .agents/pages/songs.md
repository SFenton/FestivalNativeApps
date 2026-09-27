# Songs (`/songs`) - not yet certified

**Apple recovery nuance:** The iPhone `TabView` retains a failed Songs view; its single `.task` keyed by publication **and visibility** must retry when the tab returns, even if Settings fetched a valid catalogue at the same generation. A canceled older request must not overwrite the replacement with a late, unrelated HTTP error. iPad/macOS split navigation recreates Songs on a section switch, so their initial `.loading` task recovers independently; only the iPhone test proves the retained-error fix. The native SwiftUI service-error stack retains heading/action semantics and scalable text after iOS 26.5's system `ContentUnavailableView` failed the unwaived Dynamic Type audit. It centers when content fits and scrolls vertically at large Dynamic Type; the iPhone26.5 `AccessibilityXXXL` test asserts text really grows and Retry is reachable above native chrome in portrait and landscape. Keep `.refreshable` on the **loaded List**, not the error ScrollView: replacing the source of an active refresh can cancel it and strand a failed screen on a spinner.

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:340-1380`, `src/hooks/data/useFilteredSongs.ts:66-313`, `src/pages/songs/modals/{SortModal,FilterModal}.tsx`, `src/pages/songs/components/{SongRow,InvalidScoreIcon}.tsx`. This spec reflects a dirty source worktree; see the source snapshot before asserting parity.

**Input and flow:** `GET /api/publication`, then conditional `GET /api/songs` (ETag/304 accepted only within that publication). A selected player adds profile scores/FC/valid-score substitutions; a selected band adds band song rows, member intersections and band-combo assignments. Shop data, nine visible instruments, eight metadata toggles and a saved song-filter state affect rows and sort/filter options. Search debounces 250 ms. A row goes to `/songs/:songId`, appending `?instrument=` when filtered. Its invalid-score warning is a *different accessible action* that explains fallback/over-threshold status and can navigate to Settings.

**Mobile navigation:** no profile means Songs, Leaderboards, Settings; a player or band enables Suggestions and Statistics, with Compete/Rivals rules described in `BottomNav.tsx:45-100`. Re-tapping Songs returns to the tab root; switching away/back restores its prior nested route. On iPad and Duo let native size classes and safe areas place bars instead of copying the web's uncommitted viewport detector.

**Controls and state transitions:**

| Control | Reachable states and dependent effects |
|---|---|
| Catalog/list | loading, error, no results, populated, warm offline/stale, publication changed; sections, virtual rows (web estimates 122/68, overscan 8), quick-link scroll and restored position |
| Search | empty, typing (250 ms debounce), matching, punctuation/diacritics, no results; query changes list and quick-link groups |
| Instrument | all / one of nine visible charts; changes score validity, row chips, sort/filter modes and Detail's initial instrument |
| Sort | title and conditional score/percentage/season/FC/difficulty/shop/band modes, direction, priority reorder; modal draft unchanged/changed/discard-confirmed/applied/reset; see [Sort control spec](../controls/songs-sort.md) |
| Filter | instrument and member/FC/score/shop/difficulty/season/percentile/stars; band conflicts block Apply, shop-hidden removes choices; no profile has Sort but no Filter dock action |
| Score warning | valid / valid fallback / no valid fallback / over threshold; modal action distinct from row navigation |
| Artwork | randomized animated, reduced motion, Save-Data, invisible/paused, no art; see `../controls/artwork-background.md` |

**Intentional source corrections:** keep missing scores last in both sort directions; normalize expanded accuracy by 10,000 before 90–100% quick-link buckets. The PWA currently reverses missing-score placement and compares raw accuracy with percent thresholds (`src/utils/songSort.ts:4-9`, `src/pages/songs/songQuickLinks.ts:269-283`). Do not call these bug fixes pixel-parity evidence. Hiding Shop disables effective highlighting/filters and a stale saved shop sort but preserves the preference for re-enabling.

**Accessibility/test order:** header profile, search, notifications; page title; search, Sort, conditional Filter; section headers and rows with separate warning buttons; quick-link index; tab navigation. Test control-to-control propagation, modal draft confirm/focus restore, filtered row deep link, VoiceOver/TalkBack/Narrator labels, visual states at narrow/regular widths and actual simulator motion. All profile POSTs are fixture-only pending separate service authorization. The current Apple slice implements a fixture-backed, title-ordered Songs list, search, a scene-owned instrument filter retained across iPad/macOS section switches, native Detail/solo navigation, and an accessible notice when a changed publication or hidden instrument clears a route/filter. The native no-results `ContentUnavailableView` uses a wrapping title and bright semantic text: the default one-line label clipped under Xcode's large-Dynamic-Type audit, while the replacement passes an unwaived audit over a synthetic pure-white cover on iPhone and iPad. An instrument-only empty result says no songs **match the filters**, not that the catalogue is empty. The Songs service-error state shares the solo error's readable text and opaque Retry control over artwork. When returning to a visible failed Songs tab, retry even if the observed publication stays the same: the isolated `--fail-first-white-catalogue` fixture verifies a 503, successful white-art Settings check on generation 7, and a recovered Songs row without retaining the old error.

On headerless **live** responses, never claim the observed bootstrap verifies the bytes. After model validation, a separate bounded process-only `unverifiedSnapshot` permits warm-offline Songs with the explicit **"Offline - last seen songs (publication unverified)"** banner. Raw or malformed bytes are never retained, a cold launch has no snapshot, and a known generation change clears it. Verified ETag caching remains separate. Core/macOS hosted tests cover these states; a native iPhone/iPad test against a **self-stopping** local fixture proves warm background→resume→real connection-loss fallback, the rendered/wrapping accessible banner and cold-launch expiry. This does not certify profile rows, full Sort/Filter modals, quick links, persistent cold-launch filter state, broad accessibility postures or full page parity; those remain `pending`.

**New anonymous Sort slice, not Songs parity:** The top toolbar opens a native draft sheet for title, artist, year, duration or conditional public Item Shop and direction. Only Apply changes catalogue row order; changed Cancel confirms discard, Reset returns to Title A-Z *as a draft*, and the applied preference survives a cold launch. The Swift comparator runs after search and chart filtering, treats missing year/duration as zero like the PWA, and adds a stable song ID for identical titles. A validated Shop feed (including genuinely empty) enables membership sorting; with **no validated feed retained**, an absent/failed read disables that choice, and hiding Shop removes it. Either condition pauses a saved Shop preference with a Title-order notice in the saved direction without erasing it; restoration resumes when Shop and its feed return. A failed refresh after valid data is retained keeps sorting with an explicit error disclosure. The source groups a sorted Shop list into first-seen **Leaving Tomorrow / In Shop / Not In Shop** buckets, showing headings only for at least two nonempty groups. Native now uses those same section rules; before-and-after matched fixture captures exposed and then resolved a missing-header gap, not overall visual parity. The PWA phone uses a lower Search/Sort dock and a bottom sheet, while iOS 26's toolbar Sort originally overlapped its system tab; native now uses a top toolbar and a full-height system sheet. Matched fixture-backed PWA phone/tablet Sort captures show six anonymous modes, including still-unported Has FC, with hint/direction arrows and red Reset; native has at most five inline choices, a segmented direction control, an in-form Reset and fixed Cancel/Apply. A selected source WebKit case and exact iPhone/iPad native case prove Item Shop row/section order in both directions. Do not expose unbacked FC/profile/band modes as empty success. An iPhone 26.5 `.all` audit passed on default, changed and new Shop-choice sheets; iPadOS 26.5 reports unnamed "Potentially inaccessible text" and remains a full-audit gap despite scroll-reachable Reset and measured header/action contrast. The iPad grouped headers' reported accessibility frames span both split-view panes; selected rendered text contrast is measured in the visible detail pane, **not** evidence of correct VoiceOver focus bounds. Neither screenshot set proves responsive landscape, largest Dynamic Type, all mode states, quick-link navigation or VoiceOver focus; keep the complete Songs route `partial`.

The grouped-Songs iPhone 26.5 `.all` audit passed once with semantic
`.headline` headings but later returned a nil-element Dynamic Type
failure in a source-identical run. Keep that full audit pending, not
waived or declared certified; selected visible headings meet ≥4.5:1.
This also does not resolve iPad's reported full-window focus frames.

The top native **Item Shop** action now pushes an independent public
feed without changing the three-tab phone shell. Hiding Shop removes
that action and returns an existing Shop route to Songs with a notice.
The same validated feed now paints **New/Leaving** red/gold borders
and accessible icons on Songs cards and an official Shop action on
Detail. Selected iPhone/iPad fixture tests prove that the app's
hide/highlight settings change those controls; a real Shop HTTP 503
shows a visible Retry/status error instead of silently claiming no
song is in Shop. Two additional source WebKit phone/tablet captures
show the PWA's matching red/gold *border-only* rows; native adds small
status icons as a legible, spoken distinction. Shop filtering,
band score rows, selected-profile score sorting and invalid-score
actions are **still not ported**. See [Shop](shop.md) and
[Shop offers](../controls/shop-offers.md).

**Selected-player card WIP:** A real profile action is now available
on Songs, Settings and the Leaderboards placeholder; wide Apple
sidebars visibly retain the selected player's name. The new
native search sheet separates viewing a result from selecting it.
Only a validated, response-proven player profile can decorate
Songs. In the selected iPhone/iPadOS 26.5 fixtures, a switched
player changes the **actual** score from 99,900/non-FC to
99,800/explicit gold-and-spoken FC for the same Lead song.
For positive selected scores with icons off or one chart filtered,
the native card now projects **separate typed fields in source
default order**: right-aligned Score or the next renderable
field, FC/Accuracy, percentile tier, five white or five gold
stars, inverted current season, catalogue Intensity bars and
player game difficulty. Settings switches independently update
their backed fields; selected filtered Intensity occurs **once**
in the pill row, and icons-off unfiltered Intensity now appears.
Hiding Lead changes
the unfiltered card to an explicit Bass no-score or uncharted
state rather than leaking a hidden Lead score. An identity
survives cold relaunch but its score bytes do not: the app
re-fetches under the observed publication and displays
loading/403/syncing failures instead of anonymous-looking
success. A selected player's percentile derives from
`rank/totalEntries`, not raw `pct`, and uses the source
Songs buckets: rank two of 26 reads **Top 10%**, and
rank one of a million never rounds to "Top 0.0%"
(`packages/core/src/app/formatters.ts:74-83`).
Zero is presented as **no score**, not a misleading
Score 0 label. Last Played prefers the service's `vlp`
over `lp` when available; a real seven-digit
`DateTime.ToString("O")` fixture parses correctly.
HTTP 200 does **not** prove the account is registered.

When a selected player's published scores are available,
the native All instruments row now uses every **enabled**
chart's status from the existing per-song score index if
Show Instrument Icons is on. The four source fill states
(FC gold, scored green, no score red, uncharted muted)
have a second native-drawn shape and spoken chart/status;
zero-score FC is explicitly inconsistent instead of gold.
Player 2 has a coherent extra **Pulse Drums** score and
matching mock Drums chart; deliberately empty Bass
leaderboards remain untouched. Icons off or one selected
chart keeps the native **first visible/filtered instrument**
summary and independently saved metadata. This first-visible
fallback differs from the PWA's default Lead when Lead is
hidden. The native card still lacks editable metadata order,
precomputed invalid-score variants, a score warning action,
selected-profile sorting, band assignments and profile-aware
Detail controls. When Filter Invalid Scores is enabled,
the raw player-card score is deliberately withheld with a
visible pending message until the `ml`/`vs`/`rt` selection
policy is ported; Solo requests still use their separately
verified leeway query. A band-search GET can write in the
service's missing-projection fallback, so native clients
must not call it. The paired **3/3 + 3/3 per-device** selected
matrices, **2/2 per-device** search Retry checks, and final
**7/7 per-device** selected/anonymous fixture regression prove only named
fixtures, not responsive/PWA visual parity, full audits,
95%/90% coverage or live access.
See [profile selection](../controls/profile-selection.md).

The same synthetic selected account was captured by fixture-only
source WebKit tests at phone and tablet widths (**2/2**) and native
iPhone/iPad tests. Source search results lead to the player route.
The comparison explicitly turns **source instrument icons off**:
the selected Songs card then puts 99,800 at the right, a skewed
gold 97.9% accuracy badge and Top 10% bucket beside separate
stars/season/intensity/difficulty information
(`FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:49-90,173-269`,
`FortniteFestivalWeb/src/components/songs/metadata/ScorePill.tsx:17-35`).
When a selected player's unfiltered row has instrument icons
enabled, the source instead suppresses per-chart metadata and
shows the enabled instrument status chips: FC gold, scored green,
no score red, unavailable muted
(`FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:191-200,264-271`,
`FortniteFestivalWeb/src/components/display/InstrumentIcons.tsx:110-122`).
Native's new icons-off compact row uses top-trailing Score
and source-ordered, right-aligned metadata pills with a
visible/spoken **FC 97.9%** instead of React's percentage-only
skewed gold badge. The source WebKit phone wraps 3+3 and
820px tablet uses one line; a typed SwiftUI host paints
those states but native device pixel parity is not claimed.
React drops Last Played under Title whereas native deliberately
retains the working toggle/date until its sort is implemented.
The native score/pill/Shop geometry still differs. A second
fixture-only **icons-on WebKit pair** now asserts all nine
source chip keys and computed colors at phone/tablet widths:
**4/4** selected WebKit cases pass across both modes.
Native Swift hosted tests paint the four colors and reflow
at 208/390/700 widths. A serial **10/10 on each** native
iPhone/iPadOS 26.5 matrix now proves default player
chips, green Drums after a switch, instrument hiding,
icons-off/filtered numeric scores, invalid-filter pause,
available-empty, empty Bass, and AX group reachability.
The native iPhone wraps nine chips 5+4 like the source
phone fixture, but native iPad's system split detail wraps
5+4 where the source full-width WebKit tablet shows one
row. The source WebKit case now asserts the **5+4/9**
row groups by chip positions, not merely by screenshots.
AX-only full-width title and chip stacking is scoped to
the available chip mode; other Song states retain the
previous native row geometry. A **separate 4/4 iPhone
and 4/4 iPad post-review** run proves those edited chip,
anonymous-AX, status and deselect paths. This
comparison is not a full glyph, artwork, first-run,
focus or pixel-parity certification. Source first displays a page-specific
Filter Songs carousel over selected Songs; native does not.
Source selection adds conditional destinations while native
keeps three tabs. The PWA captures intentionally dismiss that
overlay before the unobstructed Songs comparison. See the
fixture-backed comparison in `tools/visual/pages.spec.ts`; the
captures are private evidence, not redistributable artwork.
The card, first-run and navigation controls stay `pending`.
The separate pinned 8776 synthetic edge case paints a long
title, one seven-digit selected score and Shop New with a
matching Solo chart, not a production or account mutation.
Focused iPhone/iPadOS 26.5 **1/1 per device** journeys prove
score/pill right edges within 2pt, FC versus graded 4.5:1
badge text and no Shop collision; iPad Hide/Show Sidebar
and both AX5 long-title/Shop states remain responsive.
Source fixture WebKit long-title cases pass **2/2** but
marquee/truncate the title where native wraps it. Source
also displays formatted duration (6:06) and native Songs
does not yet; retain this as an explicit content gap.
A later review added visible/spoken **Drums chart** context
for a positive non-Lead score, actual scaled pill insets and
one native star plus a readable count at accessibility sizes.
The isolated 8776 profile now has a fractional Last Played date,
which native deliberately shows under Title while source hides
it. A restored Settings Form may open below Instruments, so the
native automation scrolls back before changing Lead/Bass.
At AX5, a wrapped date initially missed the card's trailing
Shop edge by 14pt on iPhone and 57pt on iPad; using the pill's
real fitted width resolved both focused device assertions to
within 2pt. An earlier **10/10 per-device** matrix predates
these review changes. A fresh source-frozen **10/10 on each**
iPhone and iPadOS 26.5 matrix now passes those exact updated
cases with source WebKit **6/6**, but retain zero route/control
certifications until the full gates are complete.
The earlier source-frozen serial **10/10 on each** iPhone
and iPadOS 26.5 regression matrix retains structured
metadata, selected/anonymous chip states, genuine empty
Bass, Shop and Detail evidence together. Neither that
targeted `--no-coverage-gate` run nor the compared
portraits certifies the full Songs route or other platforms.
The current full SwiftPM UX result is **5113/8874 (57.62%)**,
and the paired iOS UI/app subset is **3166/4419 (71.65%)**;
both remain below the 90% bar despite passing device journeys.
For native AX-size list traversal use `fst.songs.list` instead of
selecting a CollectionView by a child that will disappear on
virtualization. Stack full-width title/artist before artwork and
the status row at largest text; the focused iPhone test performs
a real swipe and proves the **entire** chip group clears the system
tab, whereas a mere `isHittable` check permitted an obstructed
bottom row. That narrow device result is not a full iPad focus audit
or a completed responsive geometry comparison.

The default Apple Debug/Release app now reads this **real public Songs endpoint** over HTTPS; native UI automation explicitly overrides it with loopback fixtures. A read-only Swift-client probe decoded 728 live Songs on 2026-09-25 and an already-running iOS 26.5 app rendered actual catalogue rows and album art. The screenshot is private session evidence, not a committed third-party artwork asset or a PWA/native layout parity comparison. Run `bash tools/apple_live_service_smoke.sh --read-public-live` for a bounded, aggregate-only wire check; never add production payloads or account identifiers to fixtures by copying this response. Catalogue counts and provenance can change on the service.
