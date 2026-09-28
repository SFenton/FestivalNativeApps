# Native macOS hosted snapshots

Use `apple/Tests/FestivalUITests/NativeHostedSnapshot.swift` to test
real AppKit-backed SwiftUI controls without opening the macOS app.
`ImageRenderer` paints yellow crossed placeholders for some native
`Form`, `Picker`, `TextField` and `List` controls; a rendered image
with those placeholders is **not** visual or state evidence.

1. Construct a `FestivalSession` with an in-memory transport that
   rejects writes, privileged keys, selected-profile headers, wrong
   routes and mismatched publication pins. For error states, a
   deliberately throwing factory is valid; never fall through to
   production. Use a separate `UserDefaults` suite with
   `.defaultAppStorage` for saved control states and clean it up.
2. Apply the app's `.preferredColorScheme(.dark)` and tint; call
   `nativeHostedView` and `nativeHostedImage`. The bitmap is at the
   host's backing scale (currently 2x), not one image pixel per
   point. AppKit/ColorSync can adjust token RGB channels, so test
   geometry and actual painted foreground/selected state rather
   than demanding uncomposited token bytes. A genuinely gold Shop
   badge is not an unsupported yellow-control placeholder.
3. A lazy `List` may paint **no rows** inside an unattached host
   even when its Shop GET and catalogue GET succeeded. Attach
   only that host to `nativeHostedWindow`, assert it never becomes
   visible and retain the window through capture. Do not order
   the window forward, restart simulators, or call a snapshot a
   complete macOS GUI/VoiceOver audit. A standalone Songs Sort
   `Form` is different: an opaque app-colored bare host paints
   active blue native pickers; attaching its window produced
   inactive-looking choices. Test its *content* surface, not
   unpresented full-sheet geometry.
4. `nativeHostedPNG` compares real states and optionally writes
   original synthetic screenshots to an **existing private**
   evidence directory via `FST_PROFILE_RENDER_OUT`,
   `FST_PATH_RENDER_OUT` or `FST_SHOP_RENDER_OUT`. Do not commit
   screenshots, service payloads or downloaded game artwork.
   Validate loaded CHOpt with the checked-in schema-2 JSON and
   a generated PNG; preserve distinct Shop populated, verified
   empty and HTTP 503 states.
5. An AppKit-backed profile `NSTextField` accepts a typed
   `controlTextDidChange` delegate action; the real 250 ms SwiftUI
   search task then loads result, empty or 403/Retry states from
   a strict in-memory GET. The native `NSSegmentedControl` can
   switch Bands without a band GET, then restore Players.
   SwiftUI result buttons do **not** expose `NSButton` children
   or offscreen AX actions here: viewed/Select/focus still need
   device UI tests. A saved identity and real pinned profile
   reads also paint distinct Songs loading, 202 syncing,
   403 denial, recovered chips and corrupt-identity states.

From the repository root, run the verified **15-case** selector:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apple --filter 'profileSheet|profileAction|pathSheet|shopScreen|songsSortSheet|selectedSongsRows|songsListPaints|selectedScoreSummary|invalidMetadataFields|profileBandScope' --quiet
```

Run
`bash tools/apple_coverage.sh` alone for the full gate;
its artwork tests now time retries from the view's start
and enforce the five-request pool even if a busy host
misses the transient three-request observation.
The complete script passed twice on identical source:
**1761/1843 logic (95.55%) and 7994/8874 UX (90.08%)**.
The selected paired
iPhone/iPad UI/app report separately remains
**3166/4419 (71.65%, fail)**; host-rendered pixels do not
increase device coverage. View-result selection/preview,
complete macOS GUI automation, screen-reader focus, unported
routes and all four-platform parity remain pending.
