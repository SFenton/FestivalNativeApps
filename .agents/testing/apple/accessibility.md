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

## iPadOS audit journeys

`apple/Apps/iPadOSUITests/IPadAccessibilityAuditTests.swift` (FST Native iPad Pro 11", fixture service) audits every iPad page and sheet unwaived, collects every issue per page and writes `<mode>-<group>.json` to `FST_AUDIT_OUT` (pass `TEST_RUNNER_FST_AUDIT_OUT=<dir>` to `ios_sim.py uitest`). Groups: **browse** (Songs, Song Detail, Sort, Filter, Paths, Item Shop, Search), **rankings** (Leaderboards, Full Rankings, Player, Settings, Licenses, profile selection, What's New), **profile** (Statistics, Suggestions, Rivals, Rival Detail, Bands, Notifications).

| Mode (test prefix) | Window | Audit types |
|---|---|---|
| `ThreeColumn` | Landscape full screen: sidebar \| list \| detail | All but contrast (below) |
| `Regular` | Portrait full screen (834 pt, regular): sidebar \| list | All |
| `Compact` | Portrait ⅓ tile ("Arrange thirds", 375 pt): phone tabs | All |
| `AX1`, `AX5`, `AX5Compact` | Portrait, `-UIPreferredContentSizeCategoryName` | All but contrast |
| `BoldText`, `IncreaseContrast`, `ReduceTransparency` | Portrait; skip unless the runner sees the setting: `ios_sim.py uitest --device ipad --a11y bold-text\|increase-contrast\|reduce-transparency` | Bold Text: all but contrast; others: all |

```bash
TEST_RUNNER_FST_AUDIT_OUT=/tmp/audit python3 tools/ios_sim.py uitest --device ipad --batch-size 1 --timeout 1500 \
  --only IPadAccessibilityAuditTests/testRegularBrowse   # one group ≈ 10–20 min
```

- **Landscape contrast is not measurable on this simulator.** With `XCUIDevice.orientation = .landscapeLeft` the screenshots (and the audit's contrast sampling) stay in portrait framebuffer orientation: the landscape UI is drawn rotated with its trailing third cut off, so white-on-black rows "fail". Contrast runs in portrait; three-column contrast is the portrait sidebar \| list plus the same detail views.
- **The audit's contrast verdicts on this app are mostly false.** On iPadOS 26.5 it reports white text on the dark material cards, glass sidebar and artwork canvas as failing; measured on the run's own screenshots (brightest 3% vs median luminance in the element frame) those elements are 5–19.5:1. Treat a contrast issue as real only with a rendered measurement below 4.5:1 (3:1 for ≥ 18 pt or bold).
- `testThreeColumnReadingOrderAndTraits`: depth-first accessibility order is sidebar row → list row → detail; the sidebar's destination and exactly one song row carry the selected trait; tapping another row moves the selection (not adds) and the detail follows while the split stays. Heading traits are read from the snapshot's `traits` (readable on iPadOS 26.5); the split exposes rotor headings for the list title, the song title, Intensity and each chart and band card. Passes.

### Results (2026-10-04)

Issue counts per group (browse / rankings / profile). "Rendered < 4.5" counts contrast issues whose own screenshot measures below the threshold; the rest of the contrast issues measured 5–19.5:1 or had no element frame.

| Mode | First run | Last run | Real findings left |
|---|---|---|---|
| ThreeColumn (no contrast) | 26 / 31 / 133 | 27 / 31 / 124 (browse now reaches Filter) | Hit-area 5 → 1 (chart legend, fixed after the run); the rest are the heuristics below |
| Regular (portrait) | 72 / – / – (rendered < 4.5: selected sidebar row 3.6:1, system Filter Songs placeholder) | 70 / 64 / 281 | Rendered < 4.5: system placeholder; profile 17 rivals red texts (fixed after the run) and 4 on the system toolbar badge ("nearly passed") |
| Compact ⅓ | – | 51 / – / 241 | System keyboard prediction cells (no description) and the text-field clear button (hit area); Sort/Filter fold into a menu at this width, so their sheets are audited at regular width only. The window sits off the screenshot origin, so its contrast issues cannot be rendered-checked |
| AX5 | – | 8 / – / 65 | Song Detail artist truncated, sidebar footer name/Deselect, rival rank line and marquee names: fixed after the run (marquee wraps, footers stack). Left: system alert and search field |
| BoldText (browse) | – | 18 | None beyond the heuristics and system fields below (the runner confirmed the setting on, so `bold-text` writes the right preference) |
| IncreaseContrast (browse / profile) | – | 47 / 203 | Rendered < 4.5: none (one pill cut off at the screen's bottom edge measured 2.4) |
| ReduceTransparency (browse / profile) | – | 19 / 109 | Contrast issues fall from ~45 to 1 (browse, the system placeholder) and from 144 to 7 (profile: the system toolbar badge, "nearly passed" at a rendered 3.4:1): with the materials and glass opaque, the audit stops misjudging white text, which supports reading its translucent-surface verdicts as false |

Auditor heuristics that do not match the rendered UI (kept unwaived, listed so nobody chases them): "Dynamic Type font sizes are partially unsupported" on dynamic text styles (`.caption2` pills, stat tile labels, card headers) and "Text clipped … may be clipped at larger sizes" on one-line text; the AX5 launches show those texts growing and wrapping. "Potentially inaccessible text" with no element (Sort, Filter, Paths, profile and Notifications sheets) is unattributed. The Paths karaoke warning is a system alert (title contrast, message Dynamic Type) and the Filter Songs / Search placeholders are system search fields.

Fixed: selected sidebar rows drew accent text on the system's gray platter (rendered 3.56:1) → standard white text, tinted symbol (HIG Focus and selection: "standard text on gray when not" focused); Song Detail's transparent pinned title stayed in the tree (read twice, audited as invisible fixed-size text) → built only once the hero scrolls away; sidebar and drawer monograms were fixed-size text → images; Rival "See All" rows were 18 pt tall → 44 pt; the rankings pager's Page element measured the bare text (31 × 18 pt) → 44 pt; rivals "behind" pills and rank-drop deltas (red on dark, 2.6–3.0:1) → lighter red text (≈ 6.5:1); chart legends marked static text. Shared fixes reach iPhone too.

Open (iPad): Full Keyboard Access and keyboard focus with a hardware keyboard ([ipados.md](../../design/apple/ipados.md)); VoiceOver focus after navigation ([voiceover.md](voiceover.md)); AX1 and the compact rankings group not yet run; the viewed-player page needs its title as the ready proof (fixed in the journey after the runs); three-column contrast only through portrait.

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
