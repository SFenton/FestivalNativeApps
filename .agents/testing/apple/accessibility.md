# Apple accessibility audits

> **What:** audit rules, rendered-contrast checks and the currently open Apple audit findings. **Read when:** the accessibility phase, or when a change touches text over artwork, the tab edge or large text.

## Rules

- Run XCTest `performAccessibilityAudit` (`.all`) **unwaived**. No blanket waivers; keep failing crops/xcresults as private evidence.
- The only scoped exception: iOS 26.5 Songs "Retry Item Shop status" may report ≤1 contrast and ≤1 Dynamic Type issue for that exact identifier/label, **after** the test independently proves ≥4.5:1 rendered text (measured 18.72:1) and >1.35× AX5 glyph growth. Never extend it.
- Named visible text gets a rendered-pixel contrast assertion (≥4.5:1 text, ≥3:1 meaningful edges) from the app screenshot — token math (`tools.contrast_gate`) is not rendered evidence.
- Large text: assert real glyph growth (>1.35× at AX5) and that actions remain reachable above native chrome in portrait and landscape.
- Use `FST_FIXTURE_SCENARIO=art-white` for worst-case contrast over artwork.
- A single passing run of a flaky audit is not certification; a source-identical rerun must pass too.
- Never write `.accessibilityHidden(someBool)`: `.accessibilityHidden(false)` on an ancestor **un-hides** every descendant marked hidden (measured in macOS hosting: the fade-in wrapper exposed each Leaderboards card's decorative instrument icon, read "Lead, image" before the "Lead" heading). Use `.accessibilityHidden(while:)` (`Common/FadeInOnLoad.swift`), which applies `accessibilityHidden(true, isEnabled:)` on iOS 18 / macOS 15 and later and hides nothing before.

## Open findings (not waived)

| Screen | Device | Finding |
|---|---|---|
| Song Detail full page | iPhone 26.5 | Score rows at y≈792/849 under the Liquid Glass tab (tab starts y=791); edge/inset/footer attempts did not fix it and were reverted. Large-type Intensity labels also flagged |
| Settings full page | iPhone | Partly offscreen heading / translucent compact title reported as contrast |
| Grouped Songs (Shop sort) | iPhone | Intermittent nil-element Dynamic Type issue; saved Shop sort + failed Shop offline state has an unidentified contrast node |
| Item Shop list, Songs list | iPhone | One nil-element "Text clipped" finding each (no identifier, label or frame), reproduced on the pre-#18 Shop rows too. The shared Song row's marquee title/artist findings (Songs since the marquee landed, Shop once it reused the row) were fixed by wrapping at accessibility sizes (issue #18) |
| Karaoke path warning alert | iPhone | System alert title contrast and message Dynamic Type |
| Sort sheet, Paths sheet, profile sheet, selected Songs | iPad 26.5 | Unnamed "Potentially inaccessible text" |
| Solo launched at AccessibilityXXXL | iPad | Three nil-element "Text clipped" findings |
| Grouped headers | iPad | Accessibility frames span both split panes; VoiceOver focus bounds unverified |

## macOS without Automation Mode

Automation Mode is not authorised on this Mac ([macos host limits](../../platforms/apple/macos.md)), so macOS accessibility evidence is in-process: `apple/Tests/FestivalUITests/MacAccessibilityTreeTests.swift` hosts the real `MacRootView` over the loopback fixture service (`RivalsMockService`) and walks the AppKit accessibility tree (`macAccessibilityTree`: role, subrole, label/title/value, identifier, selected, `isAccessibilityElement`). Toolbar items come from an `NSHostingController` with `sceneBridgingOptions = [.toolbars, .title]` in a titled offscreen window ([hosted snapshots](hosted-snapshots.md)). `FST_MAC_AX_OUT=<dir>` writes tree dumps.

| Check | Result |
|---|---|
| Sidebar | `AXOutline` "Sidebar"; every row named for its destination; exactly one `AXRow` selected and it follows the destination (Leaderboards, Item Shop, Statistics) |
| Songs list \| detail | One song row reports selected; tree order sidebar → list → detail; the detail has headings |
| Every destination (Songs, Leaderboards, Statistics, Suggestions, Rivals, Compete, Item Shop) | No unnamed button, image, field or control; no image repeating the next element's name; headings present (Item Shop: none expected) |
| Toolbar | Every item labelled and tooltipped, labels unique; Songs' field placeholder "Filter Songs" |

Fixed (before → after): Leaderboards read 9 decorative instrument images before their headings (fade-in un-hiding, rule above; app-wide on iOS 18+ too) → 0; the footer's Deselect button now says "Deselect Profile"; with a player, the profile toolbar item had an empty label (the monogram was the whole label) → "Profile: <name>"; two toolbar items were named "Search" (global search and Songs' system filter field) → the global one is "Search Festival", as in Edit › Search Festival….

Still needs VoiceOver and Full Keyboard Access with Automation Mode (or a person): spoken order and phrasing in the live window, VoiceOver cursor and keyboard focus after navigation (row → detail, sheet dismissal), rotor contents, Tab loop through sidebar → list → detail → toolbar, focus rings on rows (`festivalRowButtonStyle`), sheets (Filter, Profile, Search, Notifications, What's New are window sheets the hosted window never presents), the Settings window and menu-bar commands through accessibility.
