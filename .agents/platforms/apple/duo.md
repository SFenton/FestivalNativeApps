# iPhone Duo runtime facts

> **What:** what iPhone Duo exposes to apps (displays, poses, vertical bar, reserved regions, hinge), the SwiftUI APIs that observe them, and what the simulator can and cannot script. **Read when:** building or testing Duo layouts. Layout decisions: [design/apple/duo.md](../../design/apple/duo.md).

Sources: Xcode 27.1 SDK headers/swiftinterfaces (`UIHinge.h`, `UIVerticalBarEdge.h`, `UIViewReservedRegion.h`, `UIArrangementViewController.h`, SwiftUI/SwiftUICore `.swiftinterface`/`.swiftdoc`), the device type profile (`/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype`), Apple's [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) (HIG, 2026-09-09) and [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo), and our own simulator captures (2026-09-28).

## Hardware and windows

| | Outer (cover) display | Inner (unfolding) display |
|---|---|---|
| Panel / `simctl --display` | `primary`, 1398×2034 px @3x | `primary-1`, 2007×2853 px @3x, `nativeRotation` 270 |
| Window (points) | 466×678 portrait / 678×466 landscape (measured: portrait) | 951×669 landscape / 669×951 portrait (from the profile; not yet captured) |
| Size class | compact width | regular width |
| Idiom | `.phone` (`IsLargeFormatPhone`, Touch ID, no Face ID) | `.phone` — **`userInterfaceIdiom` cannot tell the displays apart** |
| Camera | Front camera in a corner, always visible; grows into the Dynamic Island for Live Activities (`occlusion` region) | Under-display, occludes only while active |
| Fold | — | `division` region, active only while partially open |
| Corner radii (px) | 8 on the hinge side, 59 on the outer side | 55 all round |

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
| Open / close / partially fold / rotate | Device Hub (Xcode ▸ Open Developer Tool ▸ Device Hub, or `Xcode.app/Contents/Applications/DeviceHub.app`): pose buttons under the device; ⌥-click shows a hinge-angle slider. An older Device Hub lacks the pose widget | **Only by UI scripting** (operator-approved 2026-09-28): `ios_sim.py pose --set folded\|unfolded\|half\|rotate-left\|rotate-right`, `shot --set-pose/--rotate`. No `simctl` subcommand or `XCUIDevice` API; Device Hub sends private vendor HID events. Needs the operator's Accessibility grant for the responsible app ([simulator-driver.md](../../workflow/simulator-driver.md#accessibility-permission-ui-scripting)); agents never change it |
| `XCUIDevice.shared.orientation` / driver `rotate:` | Ignored on the outer display: window stays 466×678 portrait in all four orientations (re-measured 2026-09-28) | Not a rotation |
| `simctl io … screenConfig power off` | Blanks a panel; **not** a pose | — |
| Which panel is lit | `python3 tools/ios_sim.py pose` (screenshots both panels, unlit = black) | Yes (read-only) |
| Capture a panel | `shot --device duo --display outer\|inner\|auto`; `--pose folded\|unfolded\|half` fails with exit 3 and instructions if Device Hub is in another pose (`--set-pose` fixes it by scripting) | Yes |
| Record a transition | `drive --record file.mov --display outer\|inner` (`simctl io recordVideo` for the run) | Yes |
| After a Duo session | `python3 tools/ios_sim.py shutdown --device duo` (one product simulator at a time) | Yes |

- The Duo boots **closed** (outer display lit, inner black), so a pose set in Device Hub is lost whenever another lane's `boot_exclusive` shuts the Duo down; `--set-pose` re-applies it inside the capture's own lock hold. TODO(orchestrator): confirm a pose survives an app relaunch alone.
- The driver's `back` step taps the system `BackButton` first: on Duo it lives in the vertical bar, not a navigation bar.
- Camera transitions between displays cannot be tested in Simulator (Apple).

## Outer-display rotations and the camera

Portrait was captured natively. The other three rows come from the web app's measured standalone-Safari Duo detector (`FortniteFestivalWeb/src/utils/probableDuoDisplay.ts:18-24,157-170`: an 84 pt inset on the bar side, 34 pt bottom, 0 top) and Apple's "controls stay with the camera" rule. TODO(orchestrator): confirm each row natively once the operator rotates the device in Device Hub.

| Outer rotation | Camera corner | Vertical bar edge | Evidence |
|---|---|---|---|
| Portrait | top-right | trailing (right) | native capture: bar x≈396–440 pt, top safe inset 0 |
| Upside down | bottom-left | leading (left) | web detector |
| Landscape, camera top-left | top-left | leading | web detector |
| Landscape, camera bottom-right | bottom-right | trailing | web detector |

The top safe inset is 0 in outer portrait although the camera sits in the top-right corner. Only the vertical bar's inset protects that corner, so **any custom overlay that spans the full width (drawer, banners, scrubbers) must use `DeviceLayout.overlayInsets`, not just the safe area.**

## W1 shell captures (2026-09-28)

`shot --device duo --pose folded --display auto` (outer panel, 1398×2034 px). Files: `~/repos/FestivalNativeApps-lanes/duoshell/.visual-output/duo-w1/` (gitignored; not durable).

| Pose | Before W1 | After W1 |
|---|---|---|
| Folded portrait, profile, Songs | Avatar (custom view) forced a horizontal top bar beside "Songs"; bell overflowed into `…` (B1) | No top bar: bell and `person.crop.circle.fill` "Profile: <name>" in the rail, page actions in `…` (the hamburger too: the 5-tab rail fits two root items) |
| Folded portrait, anonymous, Songs | — | Hamburger, sort, bell, profile all in the rail |
| Folded portrait, drawer | Scrim dimmed the vertical bar; panel ran to the bottom edge | Panel inset by `overlayInsets` (clear of the home-indicator inset), scrim off the bar |
| Folded portrait, Player profile | Select Profile only in content | Rail: Back, Select Profile (`person.crop.circle.badge.plus`), Quick Links |
| Folded portrait, Leaderboards › Player › Back | Rail re-laid out ~7 frames after the pop (hamburger collapsed to a dot, Rank By blanked) | Mostly clean; intermittent 2–3 frame residual ([design notes](../../design/apple/duo.md#toolbar-rules-all-duo-poses)) |
| Folded upside down / both landscapes | Not capturable | **Not captured**: needs Device Hub rotation; UI scripting awaits the operator's Accessibility grant. Drawer clearance is covered by `ShellPresentationTests.duoDrawerAvoidsBarAndCamera` for all four rotations |
| Unfolded / partially folded | Not capturable | **Not captured** (same blocker). Split Leaderboards + Rivals tabs are unit-tested (`duoInnerDisplayUsesRegularSections`) |
