# Apple architecture and runtime

Use shared Swift source/packages for URLSession-backed wire models, publication consistency, session cache, screen state and branded SwiftUI controls; keep separate iOS/iPadOS and macOS navigation shells. Use SwiftUI's system `TabView`/`NavigationStack` on compact iOS and `NavigationSplitView` where appropriate on regular widths and macOS. iOS 26+ can use Liquid Glass and navigation accessories with availability checks; older supported iOS retains its system classic tab bar. Never force a hand-built Duo tab lane or copy PWA safe-area pixels.

Apple's [Duo guidance](https://developer.apple.com/videos/play/tech-talks/111466/) says use compact outer and regular inner layouts, margins and safe areas rather than device-name breakpoints. Respect camera and fold reserved regions for custom overlays; keep system navigation outside split arrangements. A Duo pose/control matrix is still **unverified**; `simctl io ... screenConfig` exposes display power/geometry but does not by itself prove a real fold posture.

Observed on the dedicated FST Duo simulator (`BC8A530D-805F-45FD-9D32-71B838C7A05F`) on 2026-09-24: `simctl io ... enumerate` listed outer 1398×2034 and inner 2007×2853 buffers; the app launched on the outer screen and loaded publication 7 from the loopback fixture. `simctl io ... screenConfig --display=<outer UUID> power off` left the inner screenshot black; the outer power state was restored afterward. A later boot restored outer rendering, but `XCUIDevice.shared.orientation = .landscapeLeft` left the outer app window at 466×678 portrait. **Neither screen power nor XCTest orientation proves an unfolded or rotated Duo pose.** Verify actual posture, window migration and camera-cutout positions through supported Device Hub controls.

**Launch-screen compatibility is a device-testing prerequisite.** Apple [TN3208](https://developer.apple.com/documentation/technotes/tn3208-preparing-your-apps-launch-screen-to-meet-app-store-requirements) requires a launch-screen Info.plist key for iOS 27 SDK uploads. Before adding `UILaunchScreen` with the native brand-color asset, the same iOS 26.5 iPhone app captured only 960×1440 of its 1206×2622 framebuffer, and the iPad only 1536×2048 of its 1668×2420 framebuffer; their letterboxed audit/crop evidence is **invalid for native-size claims**. After clean-installing the FST app with the key, captures fill both real display buffers, and targeted Songs audits with fixture-painted artwork pass without waivers. XCTest's own `UIScreen.main`/`XCUIScreen.main` can still report legacy test-runner geometry: compare the **app screenshot pixels** with CoreSimulator's `SIMULATOR_MAINSCREEN_WIDTH` and `SIMULATOR_MAINSCREEN_HEIGHT` variables, and require visible art before auditing. One native-size iPad audit still misreported white `Leaderboards` text (measured 18.49:1 on its own screenshot) as low contrast; giving every native sidebar row an opaque Fluent card surface removed that finding without suppressing any audit issues. The selected row also needs a *visible* accent bar and semibold text, not just an accessibility trait; assert its screen pixels across section switches. On deliberately white artwork, empty Songs and solo error pass unwaived iPhone/iPad audits, and three visible Settings headers pass rendered-pixel WCAG checks; a **full Settings audit remains open** because Xcode flags partly offscreen headings/compact system chrome. Recheck Slide Over/resized iPad window geometry separately; do not hardcode device sizes into production layouts. The iOS AppIcon asset is still pending: XcodeGen sets its asset name to empty while the valid launch color compiles, and distribution branding requires a separate asset/release review.

On iPhone 26.5, the system `ContentUnavailableView` error title, description and Retry action each triggered a manufacturer Dynamic Type warning despite explicit scalable font modifiers. Use the shared native `ServiceUnavailableView` with `.title2`/`.body` fonts, a heading trait and an opaque ≥44-point Retry control for Songs and solo service failures. Its centered `ScrollView` expands past the visible height at large text sizes; assert real `AccessibilityXXXL` title growth, then scroll that **nested content**, not the app root, until Retry sits above native navigation in portrait and landscape. Verify its full unwaived audit on the same runtime, rather than waiving or relying on an iPad-only pass; Settings' full-page white-art audit is a separate open gap.

This Mac has Xcode 27.1 (build 27A9269), iOS 26.5/27.0/27.1 simulator runtimes, and **no iOS 18 runtime** as observed 2026-09-24. Set `DEVELOPER_DIR` on Xcode commands. Never touch the separately owned Home Assistant simulators, booted or otherwise. Serial testing should cover FST Duo outer orientation/cutout positions, inner layouts, iPhone on 26.x and 27.x, iPad windows, then macOS. Run accessibility audits and screenshots in hosted XCUITests; confirm VoiceOver order manually. Third-party injection/hot reload is a measured optional optimization, not a prerequisite.

The Apple `SessionResponseCache` retains publication-bound ETag responses independently from **typed and validated** headerless JSON snapshots. The latter are bounded to 16 MB/128 pages in process memory, never sent as conditional ETags or promoted to a proven generation, and cleared when a different publication is observed; process death discards both. Songs and solo score banners must distinguish **unverified last-seen offline** bytes from publication-verified offline scores; a native iPhone/iPad fixture test now proves actual Songs warm-resume and cold-expiry behavior without changing OS networking. Oversized unverified responses remain usable live but are explicitly logged as uncached; never silently present an older unverified copy as the latest offline payload. Operational endpoints remain uncached. Android/Windows offline implementations and actual iOS Core/Design device-line coverage remain separate gaps.

The Shop fixture exposed a separate **artwork** memory invariant:
an evictable `NSCache` can lose album covers when a user backgrounds
and reopens a route after connectivity disappears. `ArtworkCache` now
also strongly retains up to 16 MB/64 recent raw URLs in process; it
preserves them across backgrounding, allows off-main thumbnail decode
after NSCache eviction and clears on a known publication change or
cold launch. Do not persist art to disk or replace a missing image
with success-shaped data. A dedicated local Shop fixture waits for
actual screenshot motif-pixel proof before a test-only GET shuts
the listener, then a serial iPhone/iPad UI test reenters Shop offline
and proves the **same original pixels** are visible from memory.
This does not certify all older/evicted art or Windows/Android caches.

Debug and Release native shells default to the keyless public `https://festivalscoretracker.com` origin. `FST_API_BASE_URL=http://127.0.0.1:8765` is an **explicit Debug-only** test/development override; Release ignores it, and fixture scenarios cannot target public HTTPS. On 2026-09-25 a bounded live read decoded the public publication, 728 Songs and a ten-row Lead preview through the *actual Swift client*; a running iOS 26.5 Debug app displayed real song rows and remote artwork, not a bundled fixture. `bash tools/apple_live_service_smoke.sh --read-public-live` repeats only those three public GETs and prints aggregate counts/provenance, not titles, account IDs or raw responses. No `X-API-Key`, profile POST, scraper or maintenance request belongs in this client. The live service's publication/pinning state and counts can change; recheck them rather than freezing observed values into fixtures.

At accessibility text sizes the Solo header and freshness disclosure scroll *inside the native score List* so a narrow iPhone retains a usable score viewport above its fixed pager. Rank/name, whole unwrapped numeric score and explicitly labeled accuracy each have their own scalable line; ordinary sizes retain compact Fluent score columns. Native iOS 26.5/iPadOS 26.5 targeted tests prove both page actions and first/last score text remain reachable, and normal-size Solo pinned/offline screens pass unwaived `.all` audits. An extra `.all` probe **launched already at AccessibilityXXXL** on iPadOS 26.5 reported three `Text clipped` issues with no identified element despite readable captured rows; it is an open audit gap, not a waived pass. A full post-change device/coverage matrix remains pending under the current targeted-test workflow.

Keep the shared Solo score row's accuracy **non-gold** unless the
decoded `isFullCombo` flag is explicitly true. Native Fluent uses an
opaque-backed, 25%-tinted red-to-green pill for non-FC and a gold
outline plus visible/spoken `FC` for full combo. A nil flag is not
proof of FC. The score helper tests exact source RGB endpoints and
rejects nonfinite values; selected real iPhone/iPad pixels must show
green without gold for a non-FC row and gold without graded fill for
an FC row. At normal sizes the same fixed, scaled badge slot must
keep score ends within 1pt across FC/non-FC rows; accessibility
sizes keep the existing stacked, unwrapped score. On iPad **do**
test Hide Sidebar with Detail visible: padding inside the new
accuracy badge caused a repeatable main-thread layout loop on
that transition, while an equivalent scaled frame without
padding restored the Paths and Detail toggles. Its initial 30pt
height then failed iPad normal Solo contrast auditing; the compact
24pt frame restored page-one/page-two `.all` without hiding text
or changing the graded/gold pixels. A matched clean
`31b783e` worktree passed the same fixture test; the padded
variant hung. The full Solo List uses contained child accuracy
IDs, while Detail preview keeps its earlier inherited row ID. See
[score accuracy](../controls/score-accuracy.md).

Keep the native Detail card's View Full action **ahead of** its
lazy ten-row score preview. The source PWA puts View All after
rows, but a headerless iPhone preview plus enlarged native FC
badges made an offscreen programmatic tap reproduce a busy
SwiftUI layout loop before any full-chart request; a matched
`31b783e` app did not. An explicit user-like swipe worked, and
placing the same sole action at the top made the isolated
one-shot offline/cold-expiry journey pass with a directly
hittable target. This does not certify automatic AX scrolling
to other offscreen controls or fix the known full Detail audit.

Song Detail now uses per-chart lazy, keyless **top-ten** score previews; full Solo keeps a separate top-25 cache key and both share a scalable native score-row control. Hiding an instrument removes its preview but keeps charted Intensity visible; enabling score validation changes the preview's request `leeway`. The PWA's batched `/api/leaderboard/{song}/all?top=10` returned a deployed HTTP 403, so avoid a speculative success-shaped fallback or nine eager requests: native cards load as they appear and disclose loading, error, empty and offline states. This is still a WIP: matched phone source/native captures show missing profile/band cards and incomplete Paths, and full Detail accessibility auditing currently fails on iOS 26.5 for rows under Liquid Glass tab chrome. Keep the exact `apple-detail-preview-iphone26-audit-frames` evidence rather than applying an issue waiver; tested hard scroll edge, inset, geometry and fixed footer did **not** resolve it and were removed. Use the rendered-pixel check only as proof for the first fully visible row; other rows and large text remain pending.

CHOpt Paths have a **separate keyless public image and schema-2 JSON route** that the native Swift client decoded from one bounded live Lead/Expert probe on 2026-09-25; that fact does not unblock the Cloudflare-denied player/ranking APIs. `SongPathsSheet` pins the catalog artifact generation and publication, decodes single-frame PNG off the UI actor to a maximum 4,096px edge/24MP, and caches validated headerless bytes only in bounded process memory. Response-proven images have a separate 32 MB/16-entry LRU, and each path response is limited to 8 MB before entering either cache. Text activation rows are derived once on the client actor, not on every SwiftUI body pass. Present a native sheet with instrument/difficulty/display controls, readable Close and disabled Zoom, explicit error/Retry and provenance. Source PWA phone puts controls at the bottom; native top controls and an opaque backdrop deliberately trade pixel identity for safe-area/legibility behavior. iPhone 26.5's loaded image/text sheets passed unwaived `.all` audits after adapting zoom controls for Dynamic Type. iPadOS 26.5's full `.all` probe still reports unnamed "Potentially inaccessible text" and must remain pending despite measured visible header/Close/summary contrast. The [Paths control spec](../controls/chopt-paths.md) tracks unported drag-column order, complete responsive/focus states, macOS GUI and image performance on longer real charts.

Songs has a native Sort draft: four catalogue-field modes plus a conditional validated public Item Shop membership mode, with a segmented direction and stable comparator; `@AppStorage` persists only the applied preference. An empty validated Shop feed sorts normally. Hide Shop removes its choice, and no validated Shop feed disables it; a saved Shop preference pauses with a Title-order notice in its saved direction and resumes when validated membership returns. A failed refresh that leaves a previously validated feed available keeps sorting with an explicit update-error banner. Shop-mode Songs use source-like first-seen Leaving/In/Not buckets with labeled headings only when multiple groups exist; do not add headers or extra List spacing to Title/Artist/Year/Duration or one-bucket Shop views. Put Sort in the native top toolbar on iOS 26 because the tested bottom-toolbar button overlapped the Liquid Glass tab and activated Leaderboards instead. Keep Apply/Cancel pinned at the sheet bottom while the Form scrolls Reset fully into view on an iPad. The focused iPhone 26.5 default/changed/new-Shop-choice sheets passed `.all` accessibility audits; the iPad's full audit reported unnamed "Potentially inaccessible text" and remains pending even though Reset is demonstrably hittable after scrolling and the new-choice label met its 4.5:1 rendered text-area check. iPadOS currently reports Shop header accessibility frames as full-window even when the labels render inside the detail pane; detail-pane-anchored pixel checks prove contrast, **not** the correct VoiceOver focus rectangle. Matched PWA phone/tablet captures and pending FC/profile/band modes are recorded in [the control spec](../controls/songs-sort.md); do not conflate this with full Songs parity.

The selected iPhone 26.5 grouped-Songs screen passed one unwaived
`.all` audit after the Shop header adopted semantic `.headline`,
but a source-identical paired run produced an unnamed Dynamic Type
failure. Treat grouped-screen full audit, iPad focus bounds and
iPad full Sort audit as open; rendered header contrast is a separate
selected check, not an audit waiver.

The public Item Shop GET is independently accessible: a bounded
keyless native Swift read decoded 133 actual items (one New, one
Leaving Tomorrow) with response provenance and validated official
HTTPS URLs. `ShopScreen` pushes from Songs without adding a fourth
compact tab. Use compact original-art rows on iPhone, full-art adaptive
grid/list on iPad/macOS, but reflow to a list at accessibility text
sizes; a clipped iPad grid artist prompted this rule. Keep official
purchase and local Song Detail **separate actions**. Native selected
iPhone/iPad loaded, empty, HTTP 503, Settings hide/highlight and actual
warm-offline/cold-expiry cases pass; selected visible Shop `.all` audits
pass after the strong-art fix. A shared typed highlight policy now
paints New/Leaving Songs row borders and accessible icons, a Detail
badge and a validated official Detail action; app Settings suppress
these accents independently of the saved Shop membership. An
independent Detail task covers a cancelled Songs Shop request on
fast navigation. A targeted hosted race holds the old reply after
cancellation, lets Detail load a new offer and asserts the next
304 cannot resurrect the old ETag; the cancellation guard runs
before generic publication-cache mutation and again inside the
cache actor. Rapid device gestures remain untested.
`shop-error` vs `shop-empty` are separate loopback fixtures
so a Shop 503 cannot silently look like no songs in Shop. The PWA's
wide sidebar Shop entry, WebSocket rotation, Shop filters and
profile-dependent sorts, performance under many real images and macOS GUI remain
pending. See [Shop](../pages/shop.md).

For hosted macOS nested-route snapshots, a synchronous `ImageRenderer` of `NavigationStack` with a prefilled constant path can paint **only the brand surface** after hidden-page network tasks are correctly suppressed. Mount it in a real offscreen `NSHostingView`, allow navigation layout, and capture its bitmap instead; compare actual Detail and solo content, not two equally blank screenshots. These in-process view tests do not replace macOS GUI accessibility automation.

macOS's native UI-test scheme uses local ad-hoc signing for development only; distribution signing requires separate approval. On this host `xcrun automationmodetool status` reports Automation Mode **disabled** and requiring user authentication. The ad-hoc-signed runner timed out enabling automation before executing a test; do not enable or bypass this host setting through an agent, and do not claim a passing macOS GUI/a11y suite until a signed `.xcresult` actually contains test results.

**Profile-selection WIP:** SwiftUI keeps an icon-only named
profile action in the compact system toolbar; iPad/macOS
`NavigationSplitView` shows the actual selected player in a
Fluent opaque sidebar footer. Settings and the placeholder
Leaderboards root expose the same sheet without leaving
their current section. Only public ID/name persist across
cold launch; typed scores are process-only and refetched
with publication checks. Two serial iPhone 26.5/iPadOS
26.5 focused matrices passed 3/3 methods per device,
including cross-root/sidebar/Paths navigation and
selected Songs score/Settings states. A later 2/2
per-device rerun verified error/empty-only Retry and
real compiled UITest-source fingerprint promotion.
A source-frozen post-review **7/7 on each serial iPhone/
iPadOS 26.5 device** also proved fresh-launch identity
isolation, anonymous Intensity recovery, the selected
preview/Songs audit paths and Detail navigation. Both
products cleaned only build output after UITest source
drift, then recorded matching source hashes.
The sheet distinguishes 403/syncing/empty and blocks
any band GET that might write membership data.
Fixture-only source WebKit captures passed 2/2 at
phone/tablet widths and expose native/PWA card, first-run
and conditional-tab gaps; the layouts are **not** pixel
equivalent. A selected iPhone `.all` audit passes without
waivers, while iPad's unnamed `.all` text finding and
focus bounds are still open despite named 4.5:1 contrast.
Largest-text Select glyphs grow >1.35x on both devices.
Source-default selected-player instrument chips now have
an initial Swift Core/hosted render and matched source
WebKit fixture pass plus an exact serial **10/10 each**
iPhone/iPadOS 26.5 matrix for named chip/Settings/
AX-bound states. A separate **4/4 per-device** run
after chip-only AX scoping and exact status-label
checks preserves changed and anonymous states.
The source tablet's one chip row
becomes two in native iPad's platform split pane;
full iPad `.all`, Keyboard variants, first-run
navigation, responsive pixel parity and coverage
remain open.
An additional compact-first selected-score pill WIP puts
Score top trailing and wraps FC, percentile, stars,
season, catalogue Intensity and game Difficulty in a
source-ordered row; **focused 1/1 on each** iPhone/iPad
tests prove score/pill edges within 2pt, graded/gold
badge pixel contrast ≥4.5:1 and long-title/Shop AX5
reachability. Native iPad Hide/Show Sidebar completed
on the isolated synthetic edge without a hang. This is
followed by a serial **10/10 on each** iPhone/iPadOS26.5
source-frozen regression matrix. It is not a macOS GUI
test or source pixel parity.
Post-review focused iPhone/iPad cases also require a
visible/spoken non-Lead chart caption and a fractional
Last Played date. At AX5, a native star plus count and
scaled badge text insets avoid overflowing five stars
or touching a badge edge. The pill layout now uses the
actual fitted wrapped width: red real-device assertions
measured a 14pt iPhone and 57pt iPad date-to-Shop trailing
gap, then passed within 2pt on both after this change.
This pill-specific fix must not add padding to the
independent fixed Solo badge. A new source-frozen
**10/10 iPhone + 10/10 iPadOS** matrix passes the
post-fix selected/anonymous cases, with **6/6**
source WebKit comparison and both Apple Release
builds. Full SwiftPM logic coverage reaches
**95.17%**, but UX **57.62%** and the paired iOS
UI/app subset **71.65%** fail the 90% requirement.
Complete iPad accessibility and all-route coverage
remain open.
Mac GUI automation, older iOS/Duo poses, complete
accessibility/visual/coverage gates and real edge
authorization remain pending.

Use DocC for function contracts, `// MARK: -` sections, accessibility identifiers from the shared registry, and a dedicated logic/UI coverage split. The app can expose additive Reduce Motion/Contrast/Transparency/Background overrides, **not** an OS VoiceOver switch.
