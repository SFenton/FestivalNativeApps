# Evidence and test gates

**Two independent gates:** source line coverage of at least **95% for non-UX and 90% for UX code**, per native language, *and* complete reachable control states/transitions with visual, navigation and accessibility assertions. A screenshot or an automation count is not a line-coverage percentage.

- Logic: wire decoding (including compact fields and numeric transforms), publication pin/409 retry/304 ETag consistency, session-cache invalidation, filters/sorting and navigation guards. Negative, stale, missing, retry and offline cases belong in fixtures.
- UI: snapshots for each declared control state/theme/text scale, nested controls and controls driving other controls; page/guard/modal/back/deep-link journeys; accessibility order, labels, focus, hit targets, contrast and reduced motion. Store named test IDs and source references in the manifest; mocks replace side-effecting live endpoints.
- Android: combine host and instrumented coverage. Apple: separately measure SwiftPM package, iOS app-target and macOS app-target lines using actual coverage reports and hosted UI/a11y audits. Windows: testable view-model coverage and a proven WinUI UI-test host. Each platform's report must include the same source files that its coverage gate classifies.
- Run simulators **serially**, not in parallel; screenshots must include OS/device/pose/theme/text-size metadata. Unavailable OS runtimes and posture controls are gaps, not passes. Verify scrolling/animation at target refresh rates with representative workloads and compare Windows app/game impact in Release builds.
- For each page/control being ported, **load the real PWA layout** at matching portrait and landscape viewports (including compact, expanded and foldable-like sizes) with deterministic mock scenarios. Save matched web/native screenshots and a reviewed layout/state comparison; explain intentional Fluent and platform-native chrome deviations. A source-code reading or viewport guess cannot replace an observed visual comparison.

When the sibling web repository and its existing Playwright dependencies are present, run `cd <FortniteFestivalWeb> && FST_VISUAL_OUT=<evidence-dir> node_modules/.bin/playwright test --config <FestivalNativeApps>/tools/visual/playwright.config.mjs --project=webkit-mobile --workers=1`. The harness uses the PWA's strict scenario router, our two original fixture songs, a loopback-only art server and an unreachable Vite API proxy. Its five WebKit tests capture all four initial routes at phone/tablet portrait and landscape sizes and observe the source's real five-second cover transition. Browser viewport simulation is **not** Duo-hardware validation.

`python3 tools/verify_product.py` validates inventory consistency and prints pending surfaces. Strict mode also requires evidence for every listed page, control and state on all four platforms. On the Mac run `bash tools/apple_coverage.sh`: it tests all three **SwiftPM test bundles**, merges real LLVM line coverage by test binary, checks `apple/Sources` for missing/nested files and requires 95% logic/90% UX. Re-run this full gate after compiled-source edits; targeted tests alone cannot certify a new source snapshot.

The current full SwiftPM report (2026-09-27, after the
[hosted snapshots](native-hosted-snapshots.md), Song-row
duration and selected-player Shop Filter) measures
**1799/1880 logic lines (95.69%, pass)** and
**8491/9399 UX lines (90.34%, pass)**,
plus contrast. The preceding unchanged-source report passed
twice at 1761/1843 (95.55%) logic and 7994/8874 (90.08%)
UX; those are historical, not current-source measurements.
No production source was excluded. A passing *aggregate*
SwiftPM gate does not certify each control state, rendered
AX focus or native iOS/macOS app-target coverage. The last
passing paired iPhone/iPad UI/app subset is still the older
**3166/4419 (71.65%, fail)**; macOS GUI/VoiceOver, older
runtimes and the other platforms have separate open gates.

The script also runs `python3 -m tools.contrast_gate`, requiring ≥4.5:1 on worst-case white artwork for **only three named semantic tokens**: `textPrimary`, `textSecondary` and `gold`. Run the pure Python gate separately on non-Mac hosts; it does **not** certify system colors, blue actions or every rendered label. `FST_FIXTURE_SCENARIO=art-white` paints a deliberately white cover: native UI tests run unwaived full audits on empty Songs and failed solo scores **over painted white art**, plus a separate initial Songs error **before** the art loads, and measure three fully visible Settings section headers from actual app pixels. On iPhone 26.5, the system `ContentUnavailableView` failure title/description/action failed the Dynamic Type audit; the native scalable error stack now passes without an exception. At `AccessibilityXXXL`, the test confirms real text growth and scrolls **the error view itself** to bring Retry above native chrome in both portrait and landscape; a whole-app swipe can miss the nested scroller. Pull-to-refresh belongs only on the **loaded Songs List**: the error scroller's pull-down must not replace the only Retry action with a stuck spinner. **Settings full-page audit remains pending**: Xcode reports a partly offscreen Item Shop heading or translucent compact system title as contrast failures. Keep the exact failing crops; do not call Settings audit-certified or blanket-waive the issues.

SwiftPM does **not** measure `apple/Apps/iOS` or `apple/Apps/macOS`; Xcode sometimes omits a package target from a passing xcresult, and the separate iOS gate rejects such reports. macOS GUI automation remains blocked by the host's disabled, user-authenticated Automation Mode. `.github/workflows/contracts.yml` currently runs Python contracts/contrast only; account billing prevented its first job from starting. The category gate also parses Android JaCoCo XML and Windows Cobertura XML, merging per-line hits across host/instrumented reports. **No Android or Windows coverage has been measured yet.** Update classifiers as source directories expand rather than excluding uncovered files.

For the **measured iOS/iPadOS `FestivalUI` and mobile app entrypoint subset**, run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 tools/apple_xccov_gate.py --result <passing-iphone.xcresult> --result <passing-ipad.xcresult>`. The default `--scope paired` requires at least one complete result from each family; additional `--result` arguments join smaller, independently passing coverage shards from the **same simulator ID per family**. During the iPhone-first phase, use explicit `--scope iphone --result <passing-phone-shard.xcresult> [--result <another-phone-shard.xcresult> ...]` for a **phone-only** 90% gate; it does not certify the eventual paired iOS/iPadOS gate. Every submitted result must include both coverage targets and every corresponding source file, with matching executable-line sets and source timestamps predating **all** results. Timestamps are **not** source hashes; freeze compiled sources across shards and devices. The gate unions each **unique executable source line** before applying the unchanged 90% bar; Xcode's target summary counts SwiftUI specializations multiple times and must not be added or averaged.

The 2026-09-26 **pre-duration** broad run passed **43/43 named iPhone 26.5 cases** (excluding the known failing full Songs audit and unsupported Duo pose), but its coverage archive omitted `FestivalUI`. The serial pre-duration iPad phase passed **42/43**; its warm-offline Songs `.all` audit failed contrast. A complete pre-duration iPhone shard measured **3414/4419 (77.26%, fail)**. On the Song-row duration source, two complete iPhone-only shards later unioned **3737/4429 (84.38%, fail)**. Xcode intermittently omits `FestivalUI` even from a passing one-case result; the gate rejects such bundles. Later source-restoration timestamps invalidate reusing those prior line results as a current-source 90% pass, despite byte-identical production code. A complete phone-only and passing paired measurement remain pending.

Before the selected-player Shop Filter source edit, **32 exact iPhone methods** passed across six separate archives that each contained all 14 FestivalUI files; their unique-line union was **3907/4429 (88.21%, fail)**, 80 covered lines short of 90%. Additional Shop/intensity/artwork cases passed as tests, but three variants of their Xcode archives omitted `FestivalUI`; no lines from them entered the union. The compiled package object contains LLVM profile and coverage-map sections, so a missing Xcode target is not proof of an uninstrumented product. These reports are **historical** after the Filter's compiled-source change. A four-case current-source iPhone regression archive includes both coverage targets and measures **2916/4612 (63.23%, fail)** on that selected subset alone; no full phone-only or paired 90% measurement exists. Two focused Shop Filter journeys and a later iPhone Sort/Shop Sort/AX5 Filter **3/3** regression pass, with an unwaived loaded **and AX5** Filter-sheet audit after scrolling its Reset entirely above the pinned footer. These named states do not certify full route/control parity.

After review, the source-frozen iPhone **5/5** Shop Filter/Sort/AX5/rollover regression and separate **2/2** matched Shop badges/instrument regression pass, plus a **1/1** deselect→reselect journey. The newest current-source five-case Xcode result has both targets but only **2649/4635 UI/app lines (57.15%, fail)**; it is a selected subset, not a current 90% category pass. A scripted native hosted transport advanced publication 7→8, succeeded newer Shop/profile reads, failed newer Songs at HTTP 503 and retained two older rows without new Shop-colored borders, with both Sort and Filter visibly paused. A separate hosted selected-profile-loading state filters by same-publication Shop membership without waiting for score sync. These are host/device-specific named proofs; the exact failed-rollover **iPhone device** journey, full accessibility/route state matrix, Duo/iPad/macOS GUI and the paired line gate remain open. Two model-labeled read-only code reviews identified the generation join, but exact subagent effort/context configuration events were unavailable; do not claim verified tandem configuration.

The warm-offline audit's failing element is the Songs **"Retry Item Shop status"** button, which may or may not appear when the one-shot Songs fixture races a Shop read. The test now uses an explicit local `shop-error` scenario and waits for the actual button. A private element capture showed white glyphs on the opaque card at **18.72:1**; the native test enforces **at least 4.5:1** before auditing. A separate normal/AX5 iPhone journey proves **greater than 1.35x actual glyph-height growth** and reaches the action with short in-list drags above the system tab; full swipes skipped that narrow row. On **iPhone iOS 26.5 only**, the audit accepts **at most one contrast and one Dynamic Type report** for that exact button identifier and label after these independent checks; every other issue and other runtime remains failing. The combined Shop error/empty, AX5 and warm-offline iPhone cases passed **3/3 with this scoped exception**, not as an unwaived `.all` certification. An experimental button restyle did not remove the reports and was reverted. The iPad Songs audit remains open under the iPhone-first sequence.

At the **previous pushed WIP checkpoint**, Apple source passed **16/16 explicitly selected** native cases on each iPhone26.5 and iPadOS26.5 (excluding the known-failing Duo posture test), with a source-identical exact UI/app union of **1467/1592 unique lines (92.15%)**. These results **predate the new Solo/offline/large-text and live-default changes** and do not certify this worktree. After the score-typography fix, clean targeted iPhone26.5/iPadOS26.5 runs passed the **three changed Solo journeys per device**: dense/sparse pinned charts, a real one-shot warm-offline/cold-expiry case with unwaived normal-size audits, and actual AccessibilityXXXL score/action reachability. The Debug live-default test and bounded real Swift-client read passed separately. A source-identical full iPhone26.5/iPadOS26.5 matrix was stopped when the operator requested targeted-only passes; the later **selected 10/10-per-device** pair measures **3166/4419 unique UI/app lines (71.65%)**, still below 90% and not a full all-route suite. The earlier iOS27 5/5 target also predates these source changes. `FestivalCore` and `FestivalDesign` remain absent from Xcode coverage targets; macOS SwiftPM coverage and pixel-meter tests do **not** certify their iOS device-line coverage. The dedicated Duo four-rotation test **failed** at landscape-left (outer window stayed 466×678 portrait); selected cases are **not** a full device matrix or PWA parity certification. iOS 18 behavior is untested until that runtime is installed, and macOS app-target/GUI coverage needs host-authenticated Automation Mode.

The new WIP Song Detail top-score preview has **two targeted Core wire tests**, one hosted five-state visual test and one explicitly selected native iPhone26.5/iPadOS26.5 test per device. It proves a 10-row independent URL/ETag, overfill rejection, filtered `leeway`, visible rendered ≥4.5:1 text and navigation to a 25-row full chart. A separate iPad Settings-leeway propagation case and iPhone AccessibilityXXXL/iPad Solo-page regression case passed on their selected runs. Updated iPhone/iPad **one-shot** tests explicitly serve the preview before the first full chart, then show unverified warm-offline banners in both places and cold expiry; an iPhone white-art fixture proves the preview error is visible. Do **not** promote this into a Detail page accessibility claim: its attempted iPhone26.5 unwaived `.all` audit failed with named preview row text at y=792/849 under the system tab beginning y=791, and some Dynamic Type meter labels. The failing xcresults remain local evidence; speculative edge/inset/footer fixes were reverted. Resolving visible-row/tab overlap and running full-screen audits at all required sizes remain gate requirements. The 24-route/18-epic [backlog](../../contracts/parity-backlog.json) and `python3 tools/parity_backlog.py` fail closed on an uncatalogued route; the later full SwiftPM host measurement above passes while the separate iOS UI/app union still fails.

The **Solo FC/accuracy WIP** changes one shared preview/full row,
not profile navigation or ranking APIs. `ScoreFormattingTests`
checks the source's 0/50/98/100% rounded sRGB ramp, bounds and
nonfinite rejection; `scoreAccuracyBadgeRendersSourceStates` paints
five hosted synthetic states, including missing data, unknown FC,
zero accuracy and explicit FC with/without a percentage. The
selected `testSongDetailShowsTopScorePreviewAndFullChart` verifies
the fixture's first **non-FC** and second **FC** entries have
different accessible labels and physically different gold/graded
pixels in both Detail and Solo. The affected
`testSoloScoresAtLargestTextSize` checks the score and
explicit FC speech at AccessibilityXXXL, while the existing
portrait/landscape Solo audit guards ordinary rows. An iPad
preview test initially timed out after tapping system Hide Sidebar
despite real rows painted in a non-invasive screenshot. A 5-second
app-PID sample showed its main thread in UIKit split-view and
SwiftUI scroll layout, and the same test passed on a detached
`31b783e` baseline. Controlled iPad probes isolated new badge
padding as a trigger: a plain helper passed, padding alone hung
for three minutes, and replacing it with a fixed scaled frame
restored both the Paths and Detail sidebar-toggle tests while
keeping graded/FC color and <=1pt score alignment. **Do not**
remove this transition from the device journey or infer
responsiveness from a frozen painted frame. The first 30pt
badge height then made iPad's normal Solo page-one audit fail
with an unnamed "Contrast nearly passed" node even though
individual badge text pixels measured ≥4.5:1. The clean
`31b783e` audit passed; row/AX hiding and removing only
gold/fill did not clear it. An otherwise identical **24pt**
badge restored unwaived iPad page-one/page-two `.all` audits
without clipping badge text. Keep the full
Detail/tab-edge and other accessibility gaps pending; no
current-source 95/90 line coverage is claimed.

The changed headerless **iPhone** one-shot score journey exposed a
separate navigation regression: with View Full below ten enlarged
preview rows and the unverified-publication banner, XCTest's
offscreen auto-scroll tap stalled the native main thread before
port 8772 served the full chart. A same-simulator `31b783e`
fixture run passed; a dirty isolated run reproduced it and a
5-second app-PID sample was busy in SwiftUI layout. An explicit
swipe of Detail's own ScrollView made View Full visible and the
entire warm-offline/cold-expiry case passed. Moving the **one**
native View Full action immediately after the chart heading
also let the selected case pass with no preparatory swipe;
assert its frame is hittable above the native tab and retain
the original top-ten and full-25 wire checks. This preserves
navigation but intentionally differs from the PWA bottom CTA.
Do not infer that every other VoiceOver/offscreen auto-scroll
state is certified from this selected test.

New permanent offscreen probes use **different** local unpinned
score-one-shot listeners: 8774 for the tenth Lead score, 8775
for the empty Bass View Full action, and 8772 only for the
existing warm-offline chart. `device_fixture_plan` rejects
duplicate or shared-ordinary ports and starts eight exact-hash
stateful listeners per device; targeted Python tests assert
flags, occupied-port refusal and cleanup of only owned
processes. Both offscreen cases passed together with the
warm-offline case **3/3 on iPhone and 3/3 on iPadOS 26.5**
without sharing a consumed listener. The fixture now omits
accuracy on Lead ranks 3 (non-FC) and 4 (explicit FC) while
preserving 26 total scores. The selected preview/full device
case passed on each form factor, proving real equal-digit
score-column alignment without a badge or with FC-only, no
phantom percentage and an actual gold FC stroke. These are
synthetic bounds, not real-data/VoiceOver certification.

The focused Apple anonymous Sort slice adds two `SongCatalogSortTests` for four public-catalogue modes, missing numeric fields and stable descending ties; the single `testAnonymousSongsSortDraftApplyDiscardAndRelaunch` passed on **iPhone 26.5 and iPadOS 26.5** with exact test-name verification. It asserts changed draft, discard, actual row reorder, process relaunch, and scroll-to-visible Reset above the pinned footer. The iPhone default/draft sheet passed unwaived `.all` audits after the footer move. The iPad test measures visible header/action contrast but a separate full `.all` probe failed with an unnamed "Potentially inaccessible text"; iPad full audit and large-text/landscape/macos states remain **pending**, not waived. Two selected fixture-backed PWA WebKit Sort tests capture nearby phone/tablet default and changed modal states for structural comparison; they do not certify pixel or feature parity. Full coverage remains unmeasured for this source.

The conditional **Item Shop Sort WIP** adds two more `SongCatalogSortTests` (four total) for membership-required ordering, reversed title/artist/year ties, validated empty feed, and first-seen Leaving/In/Not groups with no heading for a single bucket. `shop-single` leaves two Songs but offers only one; a selected PWA WebKit test proves the source's ascending/descending row **and section-header** order. The native `testAnonymousItemShopSortRestoresAfterHideAndFeedFailure` checks the same row/section changes plus saved-preference pause/resume across Hide Shop, HTTP 503, a known-empty feed, full two-offer Leaving/In buckets, grouped Detail/back navigation and cold relaunch; run it and the original draft/Reset test on **each** simulator with exact selectors. The new Shop choice passed an unwaived iPhone `.all` audit; the iPad option label and two *visible grouped headers* passed actual ≥4.5:1 screenshot crops without lowering the contrast bar. For the iPad headers, XCUITest reports x=0/full-window accessibility frames even though labels render in the detail pane; sample their Y at the native search field's visible detail-pane X and **keep focus bounds unverified**. The full iPad Sort-sheet audit is also still open. Failed feeds must remain visible errors, never silently sort as empty membership. Do not interpret these selected tests as iPad full-audit, VoiceOver-order, large-text/landscape, Android/Windows or current-source coverage certification.

After replacing the Shop header's derived-weight subheadline with a
direct semantic `.headline`, the selected iPhone grouped-Songs screen
passed **one unwaived `.all`** audit, but the source-identical paired
run failed again with an **unnamed Dynamic Type issue**. The issue
handler returned a nil element/label/frame; neither Xcode attachment
named the culprit. Do not waive the finding or certify the grouped
screen from its single pass. The added deterministic iPhone/iPad
≥4.5:1 rendered-header checks cover visible text only, not complete
manufacturer audits, large-type scaling or VoiceOver focus order.

The new **CHOpt Paths WIP** uses nine focused `songPath` Core tests for URL/generation/pin/304 keys, live-shaped JSON activation rows, bounded ImageIO decoding, separate 32 MB/16-entry verified PNG LRU, pre-cache 8 MB limit and rejecting invalid headerless PNG/JSON before warm-offline caching. An opt-in read through the actual Swift client decoded a real public schema-2 Lead/Expert path and a 1024x3736 PNG without printing content; two read-only path GETs were HTTP 200. The strict loopback fixture generates an original synthetic path PNG/JSON and keeps its source hash, generation, ETag, 404/409 and read-only contract in the serial runner; relevant Python fixture/runner tests passed. Two selected WebKit image/text modal tests captured the matching source phone/tablet views. The selected `testSongPathsImageTextSwitchAndMissingDifficulty` and `testSongPathsDefaultViewFollowsSettings` exercise each native iPhone/iPad modal, zoom, instrument/difficulty/error/recovery and Settings propagation. After accessible Close and disabled-zoom fixes, iPhone 26.5's loaded image **and** text sheets passed unwaived `.all` audits. A separate iPadOS 26.5 full `.all` probe reports unnamed **"Potentially inaccessible text"**; selected title/Close/summary on-screen pixels meet the contrast assertion, but **iPad full-audit certification remains pending**. No blanket waiver, all-state UX gate, current-source line-coverage figure, or full Detail page audit is claimed.

The changed `testInstrumentVisibilityAndScoreFilterPropagation` passed
**1/1 on each device** after proving that a Settings-hidden Bass is not
offered in the Paths instrument menu, yet stays visible in Intensity.
On return from Settings, a lazy Detail score preview can overwrite the
mock's *global* last-score-query diagnostic after a full chart request.
The fixture now keeps a separate numeric-only
`/__fixture__/last-full-score-query`, updated only for `top=25`, and a
focused Python test proves a later `top=10` cannot overwrite it.
Page-two correctness is asserted by **both** the visible synthetic
rank-26 row (only served for `offset=25`) and the full-query diagnostic's
`top=25`, `offset=25`, absent leeway. Xcode once ran stale UI-test
source and a separate run emitted a zero-test result; the runner failed
closed, and **only the affected product DerivedData** was cleaned
before fresh iPhone/iPad exact test-name passes. No simulator was reset.

The **Shop WIP** adds six focused Core tests for Shop wire and effective
New/Leaving/hidden precedence (validated official outbound host/path,
order/count/flags, ETag pinning,
malformed/oversized byte rejection, unverified warm-only and cold
expiry) plus the existing artwork generation-race regression.
`tools/mock_service.py` serves two original offers with New/Leaving
badges, explicit empty/503/white-art and a separate one-shot Shop
listener. Targeted Python fixture/runner cases and two selected
fixture-backed PWA WebKit phone/tablet Shop captures pass.
`testPublicShopOffersAndSongDetailNavigation`,
`testPublicShopEmptyAndErrorStayDistinct`,
`testPublicShopSettingsHideAndHighlightPropagation` and
`testHeaderlessShopOffersRemainReadableAfterConnectionLoss` cover
Shop navigation, grid/list, real badge toggles, true empty/error,
official-vs-native actions and cache provenance on serial iPhone/iPad.
A screenshot-motif probe **first** confirms actual original artwork,
then a *test-only loopback* acknowledgement closes port 8773; the same
pixels and typed offers are asserted after warm reentry, but cannot
survive cold process launch. This caught a real NSCache-only art loss:
`ArtworkCache` now retains a strongly held 16 MB/64-URL process-only
recent tier. Loaded/empty/error and warm-offline Shop screens pass
selected unwaived iPhone/iPad `.all` audits after list reflow at
accessibility text sizes. None of these selected cases is an all-state
Shop, four-platform, full-source coverage or performance certification.

The new **Shop-to-Songs/Detail WIP** uses
`shopHighlightPolicyKeepsSourcePrecedenceAndSavedSettings` plus
`testPublicShopMembershipDecoratesSongsAndDetail` (one exact
iPhone/iPad case each) to prove validated New/Leaving borders/labels
on Songs and a distinct safe Detail Shop link. Settings highlight-off
removes the badges but retains the outbound action, while Hide Shop
removes membership UI without erasing its preference. Both selected
full **Songs** `.all` audits passed with the extra status icons; the
previously documented full Detail audit remains pending because of
score rows under system tab chrome. Two more selected WebKit captures
compare the PWA's red/gold Songs border-only states with native
border-plus-icon states at nearby phone/tablet widths. Independent
`shop-error` and `shop-empty` fixtures leave Songs populated;
`testShopFeedFailureAndEmptyStaySeparateFromSongs` passed on both
devices, showing explicit Shop 503/Retry on Songs and Detail rather
than fabricated empty membership. Very-fast Detail navigation starts
its own Shop task if Songs canceled an unfinished read. The targeted
hosted `detailShopLoadsAfterCancelledSongsRequestWithoutStalePromotion`
first reproduced an old canceled response poisoning the same-URL
Shop ETag; successful reads now check cancellation before cache
mutation and in the cache actor. Its follow-up 304 must retain the
new offer, and `canceledPublicCacheWritesNeverPromoteOldResponses`
checks canceled Shop/image actor writes. Both pass without a real
service call. Actual rapid device gestures, Shop filtering,
profile-dependent sorting and selected-player/band score cards remain open.

The generated Swift `BrandTokens.swift` contains stored constants and has no executable LLVM lines; it is the sole explicit coverage exclusion. The gate fails if a future report shows executable lines in an excluded file, and `tools/generate_tokens.py --check` separately verifies every generated token byte. Do not exclude handwritten logic or views to make a percentage pass.

For a repeatable **serial full device matrix** when the operator resumes full passes, run `python3 -m tools.apple_native_matrix --iphone-udid <FST-iPhone-ID> --iphone-os 26.5 --ipad-udid <FST-iPad-ID> --ipad-os 26.5 --evidence-dir <new-session-evidence-path>`. OS version arguments are required: an actual iOS 27 device once entered a purported 26.5 run; the runner now rejects a mismatch **before** starting fixtures, changing simulators or writing evidence. It acquires an exclusive host-wide matrix lock, discovers every current test method (excluding only the separately failing Duo pose), verifies FST device names/families, refuses any other booted simulator, starts with an already-booted product device and switches between product devices one at a time. It starts **fresh** 8767/8768, 8769 and 8771-8776 fixtures for each suite; 8771 exits after one valid unpinned Songs response, **8772 allows Detail's top-ten preview then closes after the first top-25 chart**, and **8773 closes after a validated Shop read and a test-only proof of painted Shop art**. Distinct 8774/8775 listeners reserve the offscreen Lead score and empty Bass full-chart probes; 8775 closes after the full chart request. The runner stops only fixture processes it launched. A pre-existing ordinary 8765 listener is reused **only** when its startup mock-source/JSON hashes, default launch flags and original white-song response match the frozen test inputs; a stale or unpinned service is rejected, not killed.

The runner snapshots compiled Swift, UI-test source, Xcode project/**scheme**, fixtures (including `contracts/fixtures/path-demo.json` and the original synthetic `player-demo.json`) and coverage-gate inputs before the first suite and checks those hashes during and after the run. A full matrix supplies an explicit `-only-testing` selector for **every** discovered case except Duo: Xcode previously reported a green broad-suite run while silently omitting a newly added warm-offline test. It writes non-overwriting result bundles and separate iPhone/iPad fixture logs, verifies the **exact executed test-name set** as well as counts/device identity, then runs the paired executable-line gate above. Fixture logs suppress request URLs; Xcode build logs are **raw, local evidence**, not sanitized or suitable to share. If Xcode omits `FestivalUI` or any input drifts, the matrix **fails closed**; a passing Xcode process alone is not coverage evidence. An iPad Paths setting rerun produced **zero** device/test entries despite a green Xcode process; the runner rejected it, and an Xcode build-only clean of the dedicated product iPad derived-data path restored the exact case without restarting the simulator. For focused work, add `--device iphone --only-test testSoloScoresAtLargestTextSize --no-coverage-gate` with the same explicit UDID/OS arguments; the output says coverage was not certified. Do not point the runner at Home Assistant devices or production.

The Xcode per-device budget is bounded at **20 minutes minimum,
120 seconds per exact selected method, 90 minutes maximum**. Xcode's
own watchdog permits 360 seconds by default and at most 600 seconds
for one UI method. The earlier fixed 1200-second cap truncated a
43-case iPad suite and left a partial `.xcresult` without `Info.plist`;
that archive had no usable pass count or line coverage. A later
43-case iPad invocation finished **42/43**, but its one failure was
traced to the fixture's arbitrary second-publication-read rollover,
not an iOS line-coverage result. Count-scaled timeouts do not waive
failed cases or authorize incomplete archive aggregation.

Run `python3 tools/mock_service.py --port 8765` **and explicitly launch Debug with `FST_API_BASE_URL=http://127.0.0.1:8765`** for local fixture sessions; Debug now defaults to the real public HTTPS service, while Release always uses it. The mock binds only to loopback, implements publication pin/ETag and rejects every POST. `FST_FIXTURE_SCENARIO=art-error` and `art-skip` simulate 404-only art and a valid→bad→valid catalogue without touching any CDN. `art-white` serves one original in-memory pure-white cover and a deliberately unavailable solo score so system-colored text is not hidden by the branded dark fixtures; fixture URLs and originals are generated locally.

For the **initial Songs 503 → same-publication Settings success → recovered Songs** test, start a separate `python3 tools/mock_service.py --port 8769 --fail-first-white-catalogue` listener. Restart it before **each** native device suite or rerun: its failure is consumed exactly once. For isolated headerless generation 7→8 device journeys, start separate fresh processes with `--port 8767 --unpinned --rollover-on-command` (iPhone) and `--port 8768 --unpinned --rollover-on-command` (iPad). The test-only loopback GET `/__fixture__/advance-publication` moves generation **once**, only after the UI test has actually loaded Detail and before Settings Check; wrong mode, selected headers and duplicate advances fail explicitly. The older `--rollover-on-read 2` mode remains for its independent Python wire test, not the native journey: concurrent Shop/catalogue bootstrap reads can consume an arbitrary second read before the user changes publication. For an exact Songs network-loss/resume/cold-launch journey, start `python3 tools/mock_service.py --port 8771 --unpinned --stop-after-first-songs` afresh per device. For the analogous **Solo chart** journey use `--port 8772 --unpinned --stop-after-first-score`; unlike Songs, this listener must first serve a ten-row Detail preview **and** the first full 25-row chart before it closes, causing a real connection refusal rather than a success-shaped HTTP error. Start **separate** fresh unpinned `--stop-after-first-score` listeners on ports 8774 and 8775 for the offscreen tenth Lead row and empty Bass full-chart journeys; 8774 need not serve a full chart, while 8775 must close only after its 25-row request. The runner owns and cleans up all eight stateful fixtures, including the separate publication-pinned 8776 metadata edge. Focused iPhone/iPad rollover tests each pass 1/1, but full source-identical device suites and their 90% coverage measurement remain pending. `/__fixture__/last-score-query` exposes **only synthetic numeric** score-query arguments so UI tests can prove enabled `leeway` reaches the wire and disappears when disabled.

The separate **explicitly opt-in live contract probe** is `bash tools/apple_live_service_smoke.sh --read-public-live`. It builds and uses `FestivalCore` to request exactly one public publication, the Songs catalogue and **ten rows** of one playable Lead chart, printing only aggregate counts and response provenance. It makes no profile POSTs, admin calls, artwork requests or privileged-key requests; never run it in automated fixture/coverage suites. On 2026-09-25 it decoded 728 live Songs and a ten-row preview (the previous WIP version of this probe had requested 25), and a native Debug iPhone26.5 app independently rendered real Songs and artwork. Bounded reads of deployed other nominally-public account/band search, rankings and batched song leaderboard returned HTTP 403; a ranking response named **Cloudflare Error 1010: Access denied**. Resolve authorized edge access for native public clients before describing profile or Leaderboards as live; do not spoof headers or ship the privileged service key. These are bounded production read observations, **not** permission for scraping or an assertion that service data and pinning states stay fixed.

The unpinned server omits publication response headers. **Only typed and validated** Songs/chart bytes may enter the separate 16 MB/128-entry process-only `unverifiedSnapshot`; warm-offline display must say publication **unverified**. Raw invalid bytes and operational data do not enter the new snapshot channel, and a canceled network failure cannot return offline success. An unpinned bootstrap that becomes pinning-enabled at the same ID must no longer use an unverified offline snapshot. The empty catalogue is **synthetic**, not yet a verified copy of the service wire format; replace it with fixture-verified raw data before marking Songs implemented. Never point automations at production.

The **profile-selector WIP** uses original synthetic `player-demo.json`
and mock account-search/player-profile GETs that distinguish
200-empty, 202-syncing and 403 under a publication-pinned player
read; any selected-profile header
or privileged key is rejected by the local fixture, and every POST
returns 405. `FST_UI_TEST_CLEAR_PROFILE=1` is a Debug-only launch
override for **this app's selected identity key**, not a simulator
reset or a production preference mutation. The two exact paired
iPhone/iPadOS 26.5 profile matrices passed 3/3 per device:
search/view/select/switch/deselect plus Settings/cold restore/error
states, then all-root profile actions plus the Paths sidebar
transition. The scripts freeze compiled Swift, XCTest methods and
the profile JSON hash and reject missing test names. A targeted run
uses `--no-coverage-gate`, so neither its Swift non-UX 95% nor UX
90% line bar was established. A later fixture-only source
WebKit comparison passed 2/2 at phone/tablet widths, and
two native Retry cases passed 2/2 on both devices: populated
results hide Retry; empty/error states show it. One unwaived
iPhone selected preview/Songs `.all` audit passed. Named
visible iPad text measures at least 4.5:1, but iPad `.all`
still reports unnamed "Potentially inaccessible text"
and focus bounds remain unverified. Largest-text Select
glyphs grow >1.35x on both devices with reachable sheet
actions. None of these targeted checks certifies pixel
parity, all-state accessibility, band access, a live
profile or the complete Songs/coverage gates.

A matching XCTest method name does **not** prove its
new source body executed: Xcode once ran an older screenshot
body under the correct name without producing the new
capture. The serial matrix now records a SHA-256 of
`FestivalMobileUITests.swift` in each dedicated product's
DerivedData only after exact executed case names, result
counts and simulator identity pass. On absent/drifted
source hash it **invalidates the old marker before**
running `xcodebuild clean` against **that product's
build output only**, not simulator data. A failed
H2 attempt followed by a return to H1 must clean
again rather than trusting H1's stale stamp. It
promotes no marker on failed execution; a matching
hash skips the extra clean. Focused Python
runner tests pass 23/23; an earlier paired 2/2
run confirmed iPhone reused its matching hash without
a clean while iPad performed its first scoped clean,
then both markers matched actual UITest bytes. Keep
raw build logs and PWA/native screenshots in private
session evidence, not in committed docs. Every new
`XCUIApplication` for the fixture suites now comes from
one helper that sets the Debug identity-clear flag; only
the explicit in-test cold relaunch removes it to verify
identity-only persistence. Do not clear full simulator
storage or mistake failed-test preference leaks for a
valid anonymous screenshot.
A later, separately frozen 7/7-per-device iPad→iPhone
run passed two new journeys that prove actual fresh
fixture launch isolation and anonymous Intensity
meter hide/restore, alongside selected score,
cold-restore, error/syncing and existing Detail
regressions. The UITest marker matched current
source on **both** devices only after their scoped
Xcode test-product cleans. This targeted run also
used `--no-coverage-gate`; do not infer 95%/90%
line coverage or full iPad VoiceOver focus bounds.

The **instrument-chip WIP** extends synthetic player 2
with one positive Pulse Drums score and a coherent public
mock Drums leaderboard; Bass charts remain empty for the
original offscreen zero-entry test. `SongInstrumentStatusPolicy`
performs at most nine indexed lookups, not a network call
or per-row full-profile scan. Four focused Core and two
SwiftUI hosted cases verify gating, status/score conflicts,
enabled order, actual painted gold/green/red/muted fills,
208/390/700-point reflow and AX5 host layout. The
deterministic `tools.contrast_gate` rejects glyphs below
4.5:1 and unavailable outline below 3:1 against
the **opaque native card**, not the PWA's textured
frosted surface. Generated Swift/Compose/WinUI tokens
must pass `tools/generate_tokens.py --check`.
The fixture-only WebKit selected page passes 4/4
icons-on/off phone/tablet cases; tablet width is
still an iPhone WebKit descriptor. A Debug-only
`FST_UI_TEST_RESET_SONG_CARDS=1` clears this app's
icon, visible-chart, invalid-filter and metadata
preferences on each **fresh XCTest app launch**,
never simulator data or production preferences;
the intentional selected-profile cold relaunch
removes it to test persistence. Native iPhone/iPad
**10/10 source-frozen cases on each** prove named chip
states, selected Settings transitions, empty Bass,
normal iPhone `.all`, named iPad contrast and actual
AX chip-group bounds; this remains narrower than
complete focus, high-contrast screenshot pixels,
90% UX coverage or PWA parity.
A read-only sample of one selected-player native screenshot
on **each** device found real foreground pixels inside all
four colored circles at at least 5.6:1 against their actual
painted fills. This is private, one-state evidence—not an
automated chip screenshot-contrast runner or a waiver for
the remaining variants.
Use the full-width stacked AX geometry only when published chips
are visible. Anonymous, filtered, icons-off and unavailable
profile rows retain their prior layout; a new anonymous AX
Song→Detail case **passes on both devices** after this
restriction. Exact chart/status XCTest entries disambiguate
Drums from Pro Drums and Lead from Pro Lead.
For a tall accessibility-size chip row, do **not** keep an XCTest
`CollectionView containing <row>` query across a swipe: the child is
virtualized, so the ancestor query can disappear after the scroll.
Use `fst.songs.list` as the stable native List identifier; swipe the
real collection until the requested Song row is hittable and its
score data has settled. A chip can be `isHittable` while its lower
siblings are still behind the Liquid Glass tab: assert the **entire**
named chip-group Y range lies inside the current List viewport and
above the system tab before capturing an AX screenshot. A single
iPhone AX5 case passed that focused bound check after two rejected
AX iterations; the earlier paired 10/10 matrix and separate
post-review **4/4-per-device** affected-state matrix pass.
The iPad full `.all` audit still has an unnamed text finding; do
not mistake a named group-bounds check for full VoiceOver order.

The **selected score-metadata WIP** uses typed UI-specific field order
and the same validated profile/Song publication as the chip view.
The new `metadata-edge.json` is loaded only by an exact
`--metadata-edge` option on runner-owned, **pinned** port 8776:
one long-title Song, matching seven-digit player/Solo score and
one validated Shop New offer. The ordinary 8765, empty Bass,
one-shot offline ports and website source are unchanged.
Python and Swift Core contract tests prove the edge data agree;
the mock rejects selected-profile/privileged headers and POSTs.
Fixture-only WebKit source cases passed **2/2** at phone/tablet
widths for the default six ordered fields, phone 3+3/tablet
one-line positioning, gold italic/skew and score-off primary
promotion. Another **2/2** source edge pair captured the long
phone marquee/title clipping and right-side score; the source
also shows 6:06 catalogue duration absent in native Songs.

An initial focused native **3/3 iPhone** profile/Settings/`.all`
journey passes with the structured row. Separate focused
**1/1 on each** iPhone/iPadOS 26.5 test measures field order,
Score and last-pill right edges within 2pt, FC versus graded
badge *rendered* text ≥4.5:1, FC-only after Percentage off,
Score-off primary promotion and exactly one filtered Drums
Intensity meter. A distinct edge **1/1 per device** checks
seven-digit score, Shop non-overlap, actual AX5 Shop reachability
and iPad Hide/Show Sidebar without the prior layout stall.
Native keeps its existing toggle-controlled Last Played date
under Title until the source's separate sort can be ported;
metadata order is source-default but user editing is pending.
The source gold skew is intentionally not copied to native.
Do not infer a full-screen iPad `.all`, complete visual parity,
95% logic/90% UX coverage, older iOS/Duo, macOS GUI or real-data
performance from these focused cases. A full all-case coverage
matrix is still required before certifying a route or control.
A separate source-frozen **10/10 on each iPhone/iPadOS 26.5**
matrix subsequently passed these structured metadata journeys
alongside selected chips, original empty Bass, Shop/Detail and
anonymous accessibility-size regressions. It deliberately used
`--no-coverage-gate`: that targeted result did not measure either
source category. Subsequent real AppKit-hosted tests and a full
SwiftPM run pass both host categories; paired iOS UI/app remains
below 90%. Keep the iPad full `.all` audit and
representative-data performance as release blockers.
For an optional dated selected-player card, **Last Played is
the last enabled pill**, so normal-size Score alignment must
compare with that date rather than Game Difficulty. At AX5,
require a separate trailing Shop badge and the wrapped date
to end within 2pt of one another and both remain hittable;
an iPhone 14pt/iPad 57pt failure was reproduced before
measuring the fitted width of an oversized pill, and each
focused device journey subsequently passed. The hosted
AX5 ImageRenderer alone passed at five widths even with
broken UIKit geometry: retain the *device* assertion and
read its actual screenshots, not just host pixels or an
element's existence. Scaled badge glyphs need at least
four real inset pixels at xLarge, AX3 and AX5. If Settings
retains the Metadata Form position, a test seeking an
earlier Instruments toggle must reverse its swipe after
the preferred direction cannot find the lazy control;
do not interpret eight one-way swipes as an app defect.
The earlier 10/10-per-device matrix predates these checks;
the post-fix source-frozen pair now passes exact **10/10 on
each**, with matching compiled UITest hashes and devices.
Its **3166/4419 (71.65%)** UI/app union still fails 90%;
no route or control is coverage-certified.
