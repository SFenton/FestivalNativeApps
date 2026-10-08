# iPhone Duo runtime facts

> **What:** what iPhone Duo exposes to apps (displays, poses, vertical bar, reserved regions, hinge), the SwiftUI APIs that observe them, and what the simulator can and cannot script. **Read when:** building or testing Duo layouts. Layout decisions: [design/apple/duo.md](../../design/apple/duo.md).

Sources: Xcode 27.1 SDK headers/swiftinterfaces (`UIHinge.h`, `UIVerticalBarEdge.h`, `UIViewReservedRegion.h`, `UIArrangementViewController.h`, SwiftUI/SwiftUICore `.swiftinterface`/`.swiftdoc`), the device type profile (`/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype`), Apple's [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) (HIG, 2026-09-09) and [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo), and our own simulator captures (2026-09-28).

## Hardware and windows

| | Outer (cover) display | Inner (unfolding) display |
|---|---|---|
| Panel / `simctl --display` | `primary`, 1398×2034 px @3x | `primary-1`, 2007×2853 px @3x, `nativeRotation` 270 |
| Window (points) | 466×678 portrait / 678×466 landscape (measured: portrait) | 951×669 landscape / 669×951 portrait (captured live 2026-10-04: framebuffer 2853×2007 / 2007×2853 px) |
| Size class | compact width | regular width |
| Idiom | `.phone` (`IsLargeFormatPhone`, Touch ID, no Face ID) | `.phone` — **`userInterfaceIdiom` cannot tell the displays apart** |
| Camera | Front camera in a corner, always visible; grows into the Dynamic Island for Live Activities (`occlusion` region) | Under-display, occludes only while active |
| Fold | — | `division` region, active only while partially open |
| Corner radii (pt; framebuffer mask ≈7–8 / ≈58 / ≈53) | 8 on the hinge side, 59 on the outer side | 55 all round |

- Apps move between displays on open/close as a **resize of the same scene** (compact ↔ regular); nothing tells the app "you are on the other display" except geometry, size class, `toolbarVerticalEdge` and the hinge. Keep state; never tie functionality to a pose (HIG).
- Build with Xcode 27.1+: apps built with Xcode 26 or earlier do not extend under the status bar and camera.

## The vertical bar

Toolbars, navigation controls, the tab bar, the status bar and the Dynamic Island move into **one vertical strip on the side**: on the outer display in every rotation, and on the inner display in landscape. Inner portrait keeps horizontal bars. The strip stays aligned with the hardware (same side as the outer camera; not mirrored for right-to-left). Split View multitasking puts each app's strip on its outer edge.

| Fact | Detail |
|---|---|
| Order in the strip | Dynamic Island, status bar, top toolbar items (Back/Close first, then prominent actions), a gap, bottom toolbar items, tab bar (bottom-aligned) |
| Item eligibility | Symbol items go vertical; a title-only item or a **custom view item stays in a horizontal bar**, so the system keeps a top bar just for it |
| Overflow | Items overflow bottom-to-top into a system `…` menu; tune with `visibilityPriority`, or `ToolbarOverflowMenu` |
| Compression | `toolbarVerticalCompressionBehavior(.automatic / .prefersToolbarItems / .prefersTabBar)` — automatic keeps the tab bar and overflows toolbar items |
| Opt out | `toolbarVerticalBehavior(.disabled)` (resolved per window/presentation: `TabView` uses the selected tab, `NavigationSplitView` its trailing column) — for calculators/players only |
| Per item | `ToolbarContent.axisBehavior(.automatic / .horizontalOnly / .verticalPreferred)` |
| Detect | `@Environment(\.toolbarVerticalEdge)` → `HorizontalEdge?` (nil where no vertical bar is ever used); UIKit `traitCollection.verticalBarEdge` |
| Safe area | The strip adds a leading or trailing safe-area inset; `ContentMarginGuide.container` margins can be asymmetric next to it |
| Split views | Sidebar/content columns keep horizontal bars; the detail column's bar goes vertical. Inspectors stay horizontal. Sheets on the outer display go vertical by default |

## Reserved regions and hinge (27.1 SDK)

| API | Use |
|---|---|
| `GeometryProxy.reservedRegions(kind: .occlusion / .division, options: [.includeInactive], layoutDirectionBehavior:)` → `[ReservedRegion]` (`frame` incl. `margins`, `isActive`) | Keep custom overlays off the camera and fold. Frames are mirrored for RTL by default |
| `View.onHingeChange { old, new in new.hinge }` → `DeviceHinge { status: .closed / .partiallyOpen / .fullyOpen, angle }` | Pose. Status is system-derived from angle **and orientation**; prefer it to raw angle |
| `ArrangementView { primary } secondary: { … }` + `.arrangementViewStyle(.split.axes(…) / .overlay)` | Two-pane *content* that reflows around the fold. Never put navigation inside it, and never put it inside a `NavigationSplitView`, `List` or `ScrollView` |
| `NavigationSplitView` | Expands on the inner display, collapses on the outer; equalises column widths at the fold automatically |
| `backgroundExtensionEffect()` | Extend hero/background art under the vertical bar |

The project wraps all of these in `App/Layout` ([design/apple/duo.md](../../design/apple/duo.md#infrastructure)). They exist only in the iOS 27.1 SDK (the macOS 27.0 SDK lacks them), so guard with `#if os(iOS)` + `#available(iOS 27.1, *)`.

## Simulator (alias `duo`)

| Control | How | Scriptable? |
|---|---|---|
| Open / close / partially fold / rotate | Device Hub (Xcode ▸ Open Developer Tool ▸ Device Hub, or `Xcode.app/Contents/Applications/DeviceHub.app`): buttons under the device, described **Rotate Right**, **Closed**, **Book** (partially open) and **Open** (Xcode 27.1; no Rotate Left); ⌥-click shows a hinge-angle slider | **Only by UI scripting** (operator-approved 2026-09-28; Accessibility granted 2026-10-04): `ios_sim.py pose --set folded\|unfolded\|half\|rotate-left\|rotate-right`, `shot --set-pose/--rotate`, and mid-run `drive` steps `host:pose …`. No `simctl` subcommand or `XCUIDevice` API; Device Hub sends private vendor HID events. The tool opens Device Hub and the device's window itself when missing (Xcode menu, then File ▸ New Window + the device's sidebar row) and presses through the Accessibility API (`tools/device_hub_ax.swift`): System Events sees DeviceHub with pid 0 and no windows on macOS 27 ([simulator-driver.md](../../workflow/simulator-driver.md#duo-poses-and-panels)) |
| `XCUIDevice.shared.orientation` / driver `rotate:` | Ignored on the outer display: window stays 466×678 portrait in all four orientations (re-measured 2026-09-28). Not the orientation mask: it still stays portrait with every orientation allowed (2026-10-02). Rotation needs Device Hub | Not a rotation |
| `simctl io … screenConfig power off` | Blanks a panel; **not** a pose | — |
| Which panel is lit | `python3 tools/ios_sim.py pose` (screenshots both panels, unlit = black) | Yes (read-only) |
| Split View | Entry is a drag from the Multitasking Dock (`systemDrag:<icon>><x>,<y>` driver step); superseded by the split redesign (2026-10-04), not run | Untested |
| Capture a panel | `shot --device duo --display outer\|inner\|auto`; `--pose folded\|unfolded\|half` fails with exit 3 and instructions if Device Hub is in another pose (`--set-pose` fixes it by scripting) | Yes |
| Fold/unfold while running (XCUITest) | `FST_DEBUG_DUO_WINDOW_REMOTE=1` (+ optional `FST_DEBUG_DUO_WINDOW=folded\|unfolded-landscape\|unfolded-portrait` to start) and post the Darwin notification `com.festival.debug.duo-window.<window>` from the test (`DuoShellJourneyTests`, `DuoPathsSelectorJourneyTests`): simulates the whole window (size, size classes, hinge, vertical bar) and overrides the root view controllers' size classes, so the real tab bar controller rebuilds as on a fold. Shell evidence only; the readout `fst.shell.debug.duo-window` reports the window and resolved layout | Yes |
| Drawer over the bar, rendered (XCUITest, #339) | `python3 tools/mock_service.py --port 18339` then `python3 tools/ios_sim.py uitest --device duo --pose folded --only DuoDrawerJourneyTests` (`--device iphone` runs the folded case on a standard phone and skips the unfolded one). The unfolded case uses `FST_DEBUG_DUO_WINDOW=unfolded-landscape` inside the real window, because without Device Hub scripting (macOS Accessibility) `--set-pose unfolded` is unavailable. Luminance comes from XCUITest screenshots, so `FST_DEBUG_STILL_BACKGROUND=1` (set by `FestivalApp.launch`) keeps the art still | Yes |
| Preview a portrait inner pose | `--env FST_DEBUG_DUO_POSE=half-portrait\|unfolded-portrait` (Debug builds): replaces only the hinge and fold (a 24 pt division across the middle for `half-portrait`), keeping the real window, size class and bar. Previews the portrait inner pose at outer-display size (layout evidence, not an inner-display capture); with dual-source shelved it shows the normal layout | Yes |
| Record a transition | `drive --record file.mov --display outer\|inner` (`simctl io recordVideo` for the run) | Yes |
| Fold/unfold with the app running | `drive` steps `host:pose unfolded`, `host:capture inner <path>`, `host:menu Device/Keyboard/Toggle Software Keyboard`: the host runs them mid-script, the app keeps its state | Yes |
| Hardware keyboard | Device Hub has no "Connect Hardware Keyboard" item. **Device › Keyboard › Toggle Software Keyboard** should hide the on-screen keyboard as a connected hardware keyboard would (`pose --menu`, `host:menu`), but its accessibility state read disabled in every attempt (2026-10-04; AppKit validates menu items only while the menu is open in the active app). XCUITest `key:` presses reach the app as hardware keys | Not verified |
| After a Duo session | `python3 tools/ios_sim.py shutdown --device duo` (one product simulator at a time) | Yes |

- The Duo boots **closed** and in its default orientation, so a pose or rotation set in Device Hub is lost whenever another lane's `boot_exclusive` shuts the Duo down (observed 2026-10-04); `--set-pose`/`--rotate` re-apply it inside the capture's own lock hold. A pose survives an app relaunch (`shot` after `pose --set`, same boot).
- Device Hub's device window also exposes the running app's accessibility elements (an `iOSContentGroup`); pose matching ignores that subtree, since app rows such as "… Full combo …" once matched the Open button.
- Rotate Right from the default orientation turns the inner display portrait (669×951); the inner display opens landscape (951×669).
- The driver's `back` step taps the system `BackButton` first: on Duo it lives in the vertical bar, not a navigation bar.
- Camera transitions between displays cannot be tested in Simulator (Apple).

## Outer-display rotations and the camera

Supported orientations (operator O1 (b), 2026-10-02): a device that reports a hinge (or the vertical bar) allows all four orientations via the app delegate (`App/Layout/OrientationPolicy.swift`); the iPhone Info.plist key stays portrait-only and iPad keeps its four.

Portrait and both landscapes were captured natively (2026-10-04, `~/FestivalShowcase/native-duo/poses/o1-*`, window 678×466). Upside down is never adopted: after a Rotate Right from landscape the outer display keeps the previous landscape, although the app allows every orientation.

| Outer rotation | Camera corner | Vertical bar edge | Evidence |
|---|---|---|---|
| Portrait | top-right | trailing (right) | native capture: bar x≈396–440 pt, top safe inset 0 |
| Upside down | — | — | not adopted by the system (simulator, 2026-10-04) |
| Landscape (first Rotate Right) | — | trailing (right) | native capture `o1-1-rot1` |
| Landscape (third Rotate Right) | — | leading (left) | native capture `o1-3-rot3` |

The top safe inset is 0 in outer portrait although the camera sits in the top-right corner. Only the vertical bar's inset protects that corner, so **any custom overlay laid out outside the safe area across the full width (drawer, banners) must use `DeviceLayout.overlayInsets`.** An overlay inside the content's safe area (the Songs A–Z scrubber) is already clear of the bar and adds only `DeviceLayout.cutoutInsets`; `overlayInsets` there counts the bar twice.

## W1 shell captures (2026-09-28)

`shot --device duo --pose folded --display auto` (outer panel, 1398×2034 px). Files: `~/repos/FestivalNativeApps-lanes/duoshell/.visual-output/duo-w1/` (gitignored; not durable).

| Pose | Before W1 | After W1 |
|---|---|---|
| Folded portrait, profile, Songs | Avatar (custom view) forced a horizontal top bar beside "Songs"; bell overflowed into `…` (B1) | No top bar: bell and `person.crop.circle.fill` "Profile: <name>" in the rail, page actions in `…` (the hamburger too: the 5-tab rail fits two root items) |
| Folded portrait, anonymous, Songs | — | Hamburger, sort, bell, profile all in the rail |
| Folded portrait, drawer | Scrim dimmed the vertical bar; panel ran to the bottom edge | Panel inset by `overlayInsets` (clear of the home-indicator inset), scrim off the bar |
| Folded portrait, drawer (#339, live 2026-10-07) | Art behind the rail undimmed; panel ended 42 pt above the bottom | Scrim dims the rail too (rail strip RGB ≈ 56,5,12 → 14,14,14); panel ends 8 pt above the bottom, rows above the home indicator; a tap on the rail's Profile spot closes the drawer without opening Profile |
| Folded portrait, Player profile | Select Profile only in content | Rail: Back, Select Profile (`person.crop.circle.badge.plus`), Quick Links |
| Folded portrait, Leaderboards › Player › Back | Rail re-laid out ~7 frames after the pop (hamburger collapsed to a dot, Rank By blanked) | Mostly clean; intermittent 2–3 frame residual ([design notes](../../design/apple/duo.md#toolbar-rules-all-duo-poses)) |
| Folded upside down / both landscapes | Not capturable | Both landscapes captured 2026-10-04 (see the rotations table); upside down is not adopted |
| Unfolded / partially folded | Not capturable | Captured 2026-10-04 in every inner pose ([design/apple/duo.md](../../design/apple/duo.md#decisions-per-pose)) |
