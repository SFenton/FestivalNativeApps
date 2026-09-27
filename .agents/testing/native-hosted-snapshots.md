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
   complete macOS GUI/VoiceOver audit.
4. `nativeHostedPNG` compares real states and optionally writes
   original synthetic screenshots to an **existing private**
   evidence directory via `FST_PROFILE_RENDER_OUT`,
   `FST_PATH_RENDER_OUT` or `FST_SHOP_RENDER_OUT`. Do not commit
   screenshots, service payloads or downloaded game artwork.
   Validate loaded CHOpt with the checked-in schema-2 JSON and
   a generated PNG; preserve distinct Shop populated, verified
   empty and HTTP 503 states.

From the repository root, run
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
--package-path apple --filter
'profileSheet|profileAction|pathSheet|shopScreen' --quiet`
for the **six** exact hosted cases. Run
`bash tools/apple_coverage.sh` without competing test runners when
measuring the full gate: one concurrent run made an existing
artwork-retry timing assertion observe 4.59/4.61s below its 4.7s
floor; the targeted case and the full suite passed separately.
Do not waive the assertion or describe a failing aggregate gate
as green. On 2026-09-26, the full host
report is **1758/1843 logic (95.39%, pass)** and
**7085/8874 UX (79.84%, fail)**; 902 more *covered* UX lines
are needed for 90% at this source size. The selected paired
iPhone/iPad UI/app report separately remains
**3166/4419 (71.65%, fail)**; host-rendered pixels do not
increase device coverage. Profile results/preview, broad Songs
states, complete macOS GUI automation, screen-reader focus and
all four-platform parity remain pending.
