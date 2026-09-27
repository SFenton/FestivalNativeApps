# CHOpt Paths (`fst.song-detail.paths`) - partial Apple implementation

Source: `FortniteFestivalWeb/src/pages/songinfo/SongDetailPage.tsx:163-167,302-320,634-645`,
`src/pages/songinfo/components/path/PathsModal.tsx:110-216,270-535,550-755`,
`src/pages/songinfo/components/path/PathDataTable.tsx:63-137,338-437`,
`src/contexts/SettingsContext.tsx:112-148`,
`packages/core/src/api/serverTypes.ts:176-235`, and
`FSTService/Api/SongEndpoints.cs:259-385`. Source references are hashed in
`contracts/source-snapshot.json` (55 files, seven uncommitted); the website
worktree is independently owned and was not edited.

**Real public wire:** `/api/paths/{songId}/{instrument}/{difficulty}` serves
PNG, while `/data` serves schema-2 JSON with activation beats, note frets,
OD and scores. `generationId` comes from the Songs catalogue's
`pathArtifactGenerationId`; publication pin/409 retry, ETag and distinct
image/text URL keys use the existing public client. Only decoded/validated,
size-bounded bytes can enter the process-only headerless snapshot; offline
paths distinguish verified cached from last-seen unverified responses. No
privileged API key, third-party chart asset or cold-launch file cache is
shipped. Response-proven PNG bytes have a separate 32 MB/16-image LRU,
and each path response is rejected above 8 MB **before** entering it. One
bounded, opt-in native Swift read on 2026-09-25 decoded an
actual public Lead/Expert schema-2 path (9 activations/452 notes) and its
1024x3736 PNG without a key. Both routes returned HTTP 200 and supplied
response publication provenance; no song IDs, names or asset bytes were
logged. This does **not** resolve Cloudflare 1010 on search or rankings.

| State / transition | Source behavior | Native Apple slice and open work |
|---|---|---|
| Open/default | Mobile FAB / desktop header; first visible path chart, Expert, saved image/text view | Detail toolbar Paths appears if a non-Karaoke chart is enabled; native sheet resets chart/Expert and uses the saved Settings default |
| Warning | Enabled Karaoke warns once per opening or saves "Don't show again" | Matching native alert, independent of actual chart availability; warning reset with App Settings, persistent-dismiss journey still needs automation |
| Image | Separate PNG load/error, scroll and pinch zoom | Independent public GET, decoded off main thread with a 4,096px longest-edge/24MP bound; native scroll, pinch and high-contrast zoom buttons; large-image performance needs device measurement |
| Text | Structured activation note, beat, time, OD and score table | Validated JSON, source-like five fret colors/OD bar, native activation cards and instructions; draggable desktop column order and full table geometry are pending |
| Switch | Instrument, four difficulties, image/text; old requests never paint after new choice | `.task(id:)` cancellation plus exact request-key guard; fixture proves Expert to Hard, missing Medium (explicit 404), Bass error and recovery to Lead |
| Error/offline | Unavailable content with independent text/image failures | Explicit Retry and readable errors, publication-verified/unverified warm-memory disclosure; device cold-expiry and rapid-response race need further proof |
| Dismiss/focus | Close/overlay/Escape; source dialog has no full focus trap | Native sheet, scalable Close and no gesture dismissal; keyboard/VoiceOver focus restoration and macOS GUI remain unverified |

**Settings-to-control proof:** `testInstrumentVisibilityAndScoreFilterPropagation`
turns off Bass, confirms Songs and Detail hide its selectable chart while
Intensity retains the charted value, then opens Paths and confirms Bass
is absent from its menu on both iPhone and iPad. It restores the original
visibility preference. The boundary where only Karaoke is enabled (so
Paths must disappear entirely) still needs device automation.

**Observed layout:** `tools/visual/pages.spec.ts` captures fixture-only React
image and text modals at 390x844 phone and 820x1180 tablet portraits.
`testSongPathsImageTextSwitchAndMissingDifficulty` captures the same
synthetic states on iPhone/iPadOS 26.5. PWA phone uses a bottom sheet with
controls at the bottom, translucent cards and a compact note/beat/time/OD/
score table; PWA tablet has a wide dialog with reorderable columns. Native
iPhone uses a full-height opaque system sheet; iPad has a narrower centered
sheet. Native controls sit at the top, and text cards add CHOpt instructions
and summary alongside the five colored fret markers and OD meter. This is
an intentional native/Fluent mapping, **not** pixel or complete UX parity.
The fret accents are bespoke chart-content colors, isolated to this control,
not replacements for shared Fluent tokens.

**Accessibility and test IDs:** Header/Close -> instrument -> difficulty ->
display -> freshness -> image/zoom *or* text summary/activation cards; the
background Detail route must not accept actions while a sheet is active.
IDs `fst.song-detail.paths`, `fst.paths.*` and
`fst.settings.path-default-view` live in `contracts/product.json`. On
iPhone 26.5 both loaded image and text sheets passed unwaived `.all` audits
after the disabled zoom button gained readable contrast, Close became a
scalable opaque action and zoom controls reflowed at accessibility text
sizes. The iPadOS 26.5 full `.all` probe **still fails** with unnamed
"Potentially inaccessible text"; selected on-screen header, Close and text
summary have rendered-pixel contrast checks, not an audit waiver. Largest
text from launch, landscape, tablet window sizes, full reader order and
macOS GUI (host Automation Mode requires authentication) remain pending.

Focused automated proof: nine `songPath` Core tests, a strict original PNG/
JSON loopback fixture with generation/pin/ETag/404 validation, two WebKit
PWA captures, and two selected native iPhone/iPad modal/Settings journeys.
The full 24-route parity inventory, cross-platform UI coverage and source
line-coverage bars are **not certified** by these targeted cases.

Two additional Mac-hosted tests use the
[native AppKit snapshot harness](../testing/native-hosted-snapshots.md):
real Lead/Expert Image/Text selectors, AX5, explicit failure/Retry,
then the checked-in schema-2 synthetic path and a newly generated,
bounded orange PNG. A strict in-memory transport serves only
publication-pinned keyless GETs; it rejects wrong routes/charts,
privileged/selected headers and writes. The rendered text has two
activation cards, green/red/open frets, beat/time/scores and OD
bars; the independent image has zoom actions. The test measures
**758/811 (93.46%)** hosted `SongPathsSheet` lines without
claiming draggable source table parity, iPad full accessibility
or Mac app GUI authorization.
