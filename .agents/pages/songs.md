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
selected profile/band score rows and invalid-score action are **still
not ported**. See [Shop](shop.md) and
[Shop offers](../controls/shop-offers.md).

Apple Core now decodes the source's compact player scores and
distinguishes an available HTTP 200 empty-score envelope from
registration-syncing (HTTP 202), using
only injected and synthetic loopback responses. No profile read
is initiated by the app UI yet, nor is the result wired to a
profile selector or Songs card. An HTTP 200 score list does not
prove the account is registered; a selected player's Songs
percentile must derive from rank/total, not raw `pct`.
A band-search GET can write in
the service's missing-projection fallback, so native clients
must not call it. The viewed-versus-selected state, dependent
metadata and nine rendered score-card states remain pending;
see [profile selection](../controls/profile-selection.md).

The default Apple Debug/Release app now reads this **real public Songs endpoint** over HTTPS; native UI automation explicitly overrides it with loopback fixtures. A read-only Swift-client probe decoded 728 live Songs on 2026-09-25 and an already-running iOS 26.5 app rendered actual catalogue rows and album art. The screenshot is private session evidence, not a committed third-party artwork asset or a PWA/native layout parity comparison. Run `bash tools/apple_live_service_smoke.sh --read-public-live` for a bounded, aggregate-only wire check; never add production payloads or account identifiers to fixtures by copying this response. Catalogue counts and provenance can change on the service.
