# Song Detail (`/songs/:songId`) - not yet certified

Source: `FortniteFestivalWeb/src/pages/songinfo/SongDetailPage.tsx:109-731`, `src/pages/songinfo/components/{IntensityCard,InstrumentCard}.tsx`, `src/pages/songinfo/components/chart/ScoreHistoryChart.tsx`, `src/pages/songinfo/components/path/PathsModal.tsx:130-755`.

**Entry/navigation:** a Songs row opens this page, optionally with `?instrument=` as default; auto-scroll to that instrument requires explicit navigation state. Back returns through the current native tab stack, not through unrelated tab history. Header shows static/dimmed song art, title, artist/year/duration. It links to full solo or band leaderboards, player pages, score history and optional Paths. Source PWA rows preview 10 solo scores per chart, up to 10 band scores, optional selected-member data and player history.

**Section order:** intensity for *all charted* instruments (even ones hidden in Settings); optional player history; promoted selected-band section; leaderboard cards for **visible** instruments; other Duet/Trio/Quad previews. Intensity uses `DifficultyMeter(raw:true)`; the shapes are specified in `../controls/difficulty-meter.md`. Cards distinguish loading/empty/error/entries, highlighted selected player/member and rank outside the preview. A selected player's off-preview score goes to the 25-row solo leaderboard with `page` and `navToPlayer`; a card/View Full goes to page one. More than five history scores exposes View All.

**Paths control:** shown only with path-capable instruments, header action on desktop and native-accessible action on mobile. Each opening resets instrument, Expert difficulty, saved image/text default and accordions; opening a different mobile accordion closes the prior one. Image and structured text use different publication-aware endpoints and have independent loading/success/error and revision cancellation. Text column order writes back to Settings. The unavailable-instrument warning can be dismissed for one opening or persistently. The web dialog advertises modal semantics without a focus trap: native focus containment, dismiss/back and return-focus behavior deliberately fix this defect.

**Accessibility/test matrix:** Back -> header actions -> h1/artist -> optional Paths/Shop -> intensity -> history -> promoted band -> visible chart cards -> other band previews -> tab bar. Snapshot static artwork, seven meter levels, text sizes, missing artwork, no/one/many histories, empty/error previews, and all instrument×difficulty×image/text Paths states (including rapid selector changes). Page stays `pending` until actual native content, fixture 10-row previews, visuals and reader order are measured on all platforms.

**Apple WIP slice (2026-09-25):** `SongScorePreview` lazily requests up to **ten typed/validated scores per visible chart** through the existing keyless `GET /api/leaderboard/{songId}/{instrument}?top=10&offset=0`, because the deployed `/all?top=10` batched GET currently returns HTTP 403 even though service source declares it public. A separate URL and ETag keep the ten-row preview distinct from the full 25-row Solo chart. The native card shows loading, empty, explicit error/Retry, publication-verified or unverified warm-offline disclosure, row scores and View Full. The active Settings invalid-score filter/leeway also changes each preview's request; hiding a chart removes its card but keeps its charted Intensity meter. An opt-in Swift client probe decoded a real 728-song catalogue and ten live Lead rows without an API key or logging names. Targeted Core 2/2, hosted five-state visual 1/1, native iPhone26.5/iPadOS26.5 preview 1/1 each and iPhone largest-type Solo/iPad Solo-page audits passed separately; **not** a full-source coverage or page-parity claim.

The PWA's header/view of four icon-based Intensity meters, selected-player/member spotlight/history, promoted band rows, per-row profile navigation, Shop action and full visual layout still need porting. A new full iOS26.5 Detail `.all` probe reported score text under its translucent tab bar (named row/frame evidence in session results); failed structural edge/inset/footer probes were removed rather than hidden or waived. The permanent new UI test verifies actual 4.5:1 rendered pixels for the fully visible first preview row and navigation, **not** a passing full Detail audit. Fix the tab overlap and largest-type Intensity before marking this page complete.

The shared Solo score row now distinguishes explicit FC from a graded
non-FC accuracy in **both** the lazy top-ten preview and full chart,
using a named spoken badge and separate real pixel assertions over
synthetic alternating ranks. A matched iPad baseline at `31b783e`
passed Hide Sidebar; the first native FC pill's padding caused
a repeatable split-view/hosting-scroll layout loop after that tap.
The padded build's UI test timed out after three minutes and a
5-second main-thread sample confirmed it was busy in layout, not
merely an inaccessible screenshot. Replacing badge padding with
an explicit scaled frame preserves the graded and gold states,
keeps the score column aligned and restores both Paths and
Detail's selected iPad sidebar-toggle journeys. A compact 24pt
ordinary-size badge also restores iPad Solo's normal full `.all`
audits after a 30pt row height introduced a contrast warning.
The preview badge retains its existing row accessibility ID; the
full chart exposes a distinct badge ID. These
focused states do not resolve the known Detail tab-edge audit or
selected-player row navigation. See
[score accuracy](../controls/score-accuracy.md).

The PWA's InstrumentCard places View Full **after** prefetched rows
(`InstrumentCard.tsx:300-327`). The native `SongScorePreview` now puts
its **single** View Full action directly below the chart heading
and before the loading/error/ten-score body. With a headerless
freshness disclosure, programmatically tapping the offscreen
footer action had reproducibly stalled the iPhone main thread
in a SwiftUI layout loop before requesting the full chart; the
pushed pre-FC baseline passed the same fixture journey. A real
swipe to reveal the former footer did work, but the top native
action avoids the hazardous automatic scroll, remains visible
above tab chrome, and navigates to the same full 25-row page.
The selected one-shot iPhone case asserts a direct hittable tap
without a test-only swipe and proves warm offline/cold expiry.
This placement is an **intentional native UX departure**, not
pixel parity or proof for every VoiceOver/programmatic scroll. The
native card already exposed View Full when loading, empty or failed;
moving it did **not** add those states. The local iPhone offscreen
Lead tenth-row and empty Bass actions both remain reachable, but
matched real-data navigation and focus order remain pending.

**New CHOpt Paths WIP slice (2026-09-25):** A native top-toolbar Paths action appears when Settings enables any of the eight path-capable charts; Karaoke cannot be selected for paths and triggers the source's warning until dismissed. The Swift client decodes both *real, keyless* public PNG and structured JSON with optional catalogue generation ID, distinct publication-aware ETags, bounded off-main decoding and validated process-only warm snapshots. A bounded opt-in native probe decoded one live schema-2 Lead/Expert text path and PNG; this access is independent of the edge-denied profile/rank routes. The native sheet opens at Expert and the saved image/text default, switches instrument/difficulty/display without stale results, offers pinch/button zoom and presents note frets, timing, OD and scores plus explicit error/Retry and freshness. The original synthetic fixture produced matched PWA/native image and text phone/tablet screenshots. The PWA bottom controls and wide drag-reorderable table are **not** copied: native uses top menu/segments and activation cards; native column reordering, source full table geometry, rapid-response race/focus proof, all postures and full iPad accessibility remain pending. The iPhone loaded image/text sheets pass `.all` audits; iPad `.all` reports unnamed "Potentially inaccessible text" despite selected rendered-contrast checks. See [the Paths control spec](../controls/chopt-paths.md); neither Detail nor the control is certified.

The changed Settings visibility journey now also proves a hidden Bass is
absent from **both** leaderboard actions and the Paths picker on iPhone
and iPad, while its charted Intensity remains shown. The full Solo
page-two fixture row and a separate top-25-only query diagnostic assert
the exact offset and disabled leeway; lazy top-ten Detail previews can
no longer overwrite this wire evidence.

The one-shot headerless score fixture on port **8772** must serve both the Detail `top=10` preview and the first full `top=25` score page before closing. Stopping on the preview regressed the already-tested warm-offline Solo navigation; this failure was reproduced, and the updated fixture plus targeted iPhone/iPad tests now prove warm resume, an **explicit preview offline-provenance banner** on return, full-page re-entry with an unwaived **Solo** audit, and cold expiry. A separate iPhone white-art error scenario proves the preview's visible "Scores unavailable" state before the full error page. Preview snapshots remain keyed separately from full-page snapshots; viewing only the preview cannot imply an unseen full page is cached for offline use.
