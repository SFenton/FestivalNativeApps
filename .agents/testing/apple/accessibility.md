# Apple accessibility audits

> **What:** audit rules, rendered-contrast checks and the currently open Apple audit findings. **Read when:** the accessibility phase, or when a change touches text over artwork, the tab edge or large text.

## Rules

- Run XCTest `performAccessibilityAudit` (`.all`). No blanket waivers and never a whole audit type; keep failing crops/xcresults as private evidence.
- iPhone's only scoped exception: iOS 26.5 Songs "Retry Item Shop status" may report ≤1 contrast and ≤1 Dynamic Type issue for that exact identifier/label, **after** the test independently proves ≥4.5:1 rendered text (measured 18.72:1) and >1.35× AX5 glyph growth. Never extend it.
- iPad accepts an issue only through an entry in [iPad audit waivers](#ipad-audit-waivers): a measurement of that issue in the same run, or a system control we do not own. Add an entry there and in `IPadAuditWaivers.swift` together, with its evidence.
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

`apple/Apps/iPadOSUITests/IPadAccessibilityAuditTests.swift` (FST Native iPad Pro 11", fixture service) audits every iPad page and sheet, collects every issue per page and writes `<mode>-<group>.json` plus each page's upright capture (`.png`) and element tree (`.tree.txt`) to `FST_AUDIT_OUT` (pass `TEST_RUNNER_FST_AUDIT_OUT=<dir>` to `ios_sim.py uitest`). Groups: **browse** (Songs, Song Detail, Sort, Filter, Paths, Item Shop, Search), **rankings** (Leaderboards, Full Rankings, Player, Settings, Licenses, profile selection, What's New), **profile** (Statistics, Suggestions, Rivals, Rival Detail, Bands, Notifications). An issue passes only through a waiver below; everything else fails the method.

| Mode (test prefix) | Window | Audit types |
|---|---|---|
| `ThreeColumn` | Landscape full screen: sidebar \| list \| detail | All |
| `Regular` | Portrait full screen (834 pt, regular): sidebar \| list | All |
| `Compact` | Portrait ⅓ tile ("Arrange thirds", 375 pt): phone tabs | All |
| `AX1`, `AX5`, `AX5Compact` | Portrait, `-UIPreferredContentSizeCategoryName` | All but contrast |
| `BoldText`, `IncreaseContrast`, `ReduceTransparency` | Portrait; skip unless the runner sees the setting: `ios_sim.py uitest --device ipad --a11y bold-text\|increase-contrast\|reduce-transparency` | Bold Text: all but contrast; others: all |

```bash
TEST_RUNNER_FST_AUDIT_OUT=/tmp/audit python3 tools/ios_sim.py uitest --device ipad --batch-size 1 --timeout 2400 \
  --only IPadAccessibilityAuditTests/testRegularBrowse   # one group ≈ 15–40 min (second launch per page for Dynamic Type evidence)
```

- **Captures.** `XCUIScreen.main.screenshot()`, not `XCUIApplication.screenshot()`: it covers the whole screen, so element frames (screen points) map directly, including a ⅓ window away from the origin. In landscape it arrives in portrait framebuffer orientation and is rotated upright (`IPadAuditRenderedContrast.Capture`); the app screenshot was the one cut off. Points come from the bitmap and its scale: SpringBoard's frame (1194 pt) is shorter than the 11-inch framebuffer (1210 pt).
- **Rendered contrast** (`IPadAuditPageEvidence.reading`): each recognized word (Vision) of the element's own label is measured on its own box: surface = median pixel, text = upper quartile of the pixels ≥ 1.5× away from it (the glyph core); the weakest word is the reading. Element frames alone mislead: a selected sidebar row's symbol (recognized as "0Ol") read the row at 3.6:1 instead of 13.8:1, a fixed top percentile read a 296 pt "Settings" row at 2.8:1 instead of 17:1, the glyph median read 11 pt pill text at 4.3:1 where its colours give 6:1. Elements under the tab bar, the floating page tools or the screen edge are scrolled clear with slow drags first.
- **Unattributed issues.** On iPadOS 26.5 the audit reports many SwiftUI text nodes with **no element** ("Contrast failed for SwiftUI.AccessibilityNode"; the issue's own element reference is nil, also in its private ivars). They get page-level evidence (`IPadAuditPageEvidence`): every static text in the region is measured, and every recognized line in the region must name an element.
- **Dynamic Type heuristics** (`IPadAuditTextEvidence`): for "partially unsupported" and "Text clipped" the page is launched again at AX5 (at the default size when the audit ran at AX5), the same element (identifier and label, or label and type, case-insensitive, by reading-order ordinal) is found, its text growth measured on recognized word heights (a 44 pt minimum row hides glyph growth in frame heights) and, for clipping, its text read back from the AX5 capture.
- `testThreeColumnReadingOrderAndTraits`: depth-first accessibility order is sidebar row → list row → detail; the sidebar's destination and exactly one song row carry the selected trait; tapping another row moves the selection (not adds) and the detail follows while the split stays. Heading traits are read from the snapshot's `traits` (readable on iPadOS 26.5); the split exposes rotor headings for the list title, the song title, Intensity and each chart and band card.

### iPad audit waivers

`apple/Apps/iPadOSUITests/IPadAuditWaivers.swift`. (b) = verified auditor false positive, (c) = system control we do not own. Every (b) entry is proved per issue in the same run; a waived issue stays in the JSON with its waiver id.

| Id | Kind | Audit type | Scope | Evidence |
|---|---|---|---|---|
| `contrast-rendered` | b | Contrast | The flagged element, not a system field | Its text renders ≥ 4.5:1 in the run's capture (all sizes; the 3:1 large-text allowance is not used). Below-the-fold elements are scrolled into view first. Reduce Transparency removes nearly all of these verdicts (white text on material/glass) |
| `unattributed-contrast-page-floor` | b | Contrast | No element; the page (the sheet on sheet pages) | Every static text in the region renders ≥ 4.5:1 (texts under the tab bar or page tools are scrolled clear and measured; none left unmeasured), so no node the audit could mean fails |
| `dynamic-type-grows` | b | Dynamic Type ("partially unsupported") | The flagged element, not a system field | The same element's text (recognized word height; frame height when unrecognized) is ≥ 1.35× taller at AX5 than at the audited size |
| `unattributed-dynamic-type-page-growth` | b | Dynamic Type ("partially unsupported") | No element; the page | Every visible static text is ≥ 1.35× taller in an AX5 launch of the page |
| `text-clipped-whole` | b | Text clipped | The flagged element, not a system field | At AX5 it is ≥ 1.35× taller and reads back untruncated from the capture (no ellipsis, not a cut-short prefix of its label) |
| `unattributed-text-clipped-page-whole` | b | Text clipped | No element; the page | Every leaf static text on screen at AX5 reads back untruncated; navigation-bar large titles (UIKit) are listed in the evidence but do not block |
| `unattributed-text-behind-sheet` | c | Element detection ("Potentially inaccessible text") | No element; a sheet page | Every line of text recognized inside the sheet names an element; the rest is the page behind the modal sheet, visible through the dimming and correctly outside the tree |
| `system-search-placeholder-contrast` | c | Contrast | `searchField` | UIKit draws the placeholder in `placeholderText` ("nearly passed"; "Filter Songs" core 5.6:1). HIG Search fields: use the system field. iPhone accepts the same issue (#92) |
| `system-search-placeholder-clipped` | c | Text clipped | `searchField` | A search field's placeholder is single-line by construction (global search's "Search songs or players" at AX5) |
| `system-search-clear-button` | c | Hit region | Button labelled "Clear text" | UISearchBar's 20.5 pt clear button; the field is the target |
| `system-toolbar-badge` | c | Contrast | Static text inside `fst.shell.notifications` | iOS 26 system toolbar-item badge (white on system red, ≈ 4:1 by the system colours); hidden from VoiceOver, the bell says "N unread". Left out of the page contrast floor |
| `system-keyboard-candidates` | c | Sufficient description | `other` inside the system keyboard | Empty QuickType candidate cells while the compact Search field is focused |
| (not audited) | c | – | Paths' "Some Instruments Unavailable" system alert | UIKit alert; the journey taps OK and audits the Paths sheet itself |

### Results (pre-redesign, 2026-10-05)

Raw audit issues per group (browse / rankings / profile) → issues left open after the waivers. **Pre-redesign:** measured on the always-on split layouts and pinned iPad sidebar that Lane SPLIT then replaced (on-demand split, overlay flyout); the final re-audit runs on the new shell (journeys that open the three-column split or the sidebar need updating first). Lane A11Y's last counts are the "before"; its runs had no waivers, no landscape contrast and no Dynamic Type comparison.

| Mode | Lane A11Y (before) | Lane A11Y2 raw | Open after waivers | Left open |
|---|---|---|---|---|
| Regular (portrait) | 70 / 64 / 281 | 62 / 104 / 228 | 0 / 0 / 2 | Statistics: 2 × "Potentially inaccessible text" without an element (below) |
| Compact ⅓ | 51 / – / 241 | 52 / 82 / 94 | 1 / 1 / 1 + Rival Detail unreached | Song Detail "No scores recorded yet": not found again at AX5 (lazy card), no evidence; Player "2 (66.6%)" cut at AX5 (fixed after the run: `a6d31ec6`); Statistics "88,000,000" not measurable clear of the bars; Rival Detail's proof fixed after the run (`2841bc40`) |
| AX1 (new) | not run | 27 / 29 / 71 | 0 / 0 / 1 | Statistics: the same unattributed text |
| AX5 | 8 / – / 65 | 20 / 28 / 36 | 0 / 0 / 0 | – |
| ThreeColumn (landscape, now with contrast) | 27 / 31 / 124 (no contrast) | 90 / – / – | 0 / – / – | Rankings and profile not re-run: the split layout is being replaced |
| AX5Compact, BoldText, IncreaseContrast, ReduceTransparency | see Lane A11Y's record in git history | not re-run | – | Re-run after the redesign |

Waivers applied per run are in each run's JSON (`waiver` per issue). In the regular profile group, for example: 70 `dynamic-type-grows`, 115 `contrast-rendered`, 15 `unattributed-contrast-page-floor`, 10 `text-clipped-whole`, 5 `unattributed-text-clipped-page-whole`, 6 `unattributed-text-behind-sheet`, 5 `system-toolbar-badge`.

Unattributed "Potentially inaccessible text" on Statistics (kept open): every recognized line on the page names an element, so the text the audit means is not legible to text recognition; the rotated Rank History axis titles were the first suspects and are now exposed ("Total Score axis", "Rank axis", `fa9799c1`) without clearing it. Remaining suspects: Swift Charts axis tick labels (75M, #3, dates), which are not in the tree. Not waived.

Fixed: selected sidebar rows drew accent text on the system's gray platter (rendered 3.56:1) → standard white text, tinted symbol (HIG Focus and selection: "standard text on gray when not" focused); Song Detail's transparent pinned title stayed in the tree (read twice, audited as invisible fixed-size text) → built only once the hero scrolls away; sidebar and drawer monograms were fixed-size text → images; Rival "See All" rows were 18 pt tall → 44 pt; the rankings pager's Page element measured the bare text (31 × 18 pt) → 44 pt; rivals "behind" pills and rank-drop deltas (red on dark, 2.6–3.0:1) → lighter red text (≈ 6.5:1); chart legends marked static text. Lane A11Y2: stat tile values cut at AX5 ("2 (66.6%)" → "2 (66…") → wrap to two lines, fewer and wider columns (224 pt minimum tile) and a 0.5 scale floor at accessibility sizes; suggestion rows squeezed the percentile pill to "Top…" at AX5 → rows stack and the pill wraps at accessibility sizes; the iPad sidebar footer covered the rows at AX5 in landscape → it scrolls as the list's last section at accessibility sizes (sidebar code, before the redesign notice); ranking ratings and untinted stat values in the accent blue rendered 3.8–4.2:1 → `AccentText.blue` (≈ 7:1); Rank History bars read "0 to 1" and paged-out bars stayed in the tree over the sidebar → one element per visible bar with date, rank and score; its rotated axis titles were hidden visible text → "Total Score axis" / "Rank axis"; Song Detail's hero title gained the heading trait. Shared fixes reach iPhone too.

Open (iPad): Full Keyboard Access and keyboard focus with a hardware keyboard ([ipados.md](../../design/apple/ipados.md)); VoiceOver focus after navigation ([voiceover.md](voiceover.md)); at AX5 in a ⅓ window the shared Song row breaks titles mid-word ("Fix-ture Or-bit") beside its badges (shared with iPhone; not changed here); the Statistics text above; the remaining modes and a source-identical rerun after the redesign.

## macOS without Automation Mode

Automation Mode is not authorised on this Mac ([macos host limits](../../platforms/apple/macos.md)), so macOS accessibility evidence is in-process: `apple/Tests/FestivalUITests/MacAccessibilityTreeTests.swift` hosts the real `MacRootView` over the loopback fixture service (`RivalsMockService`) and walks the AppKit accessibility tree (`macAccessibilityTree`: role, subrole, label/title/value, identifier, selected, `isAccessibilityElement`). Toolbar items come from an `NSHostingController` with `sceneBridgingOptions = [.toolbars, .title]` in a titled offscreen window ([hosted snapshots](hosted-snapshots.md)). `FST_MAC_AX_OUT=<dir>` writes tree dumps.

| Check | Result |
|---|---|
| Sidebar | `AXOutline` "Sidebar"; every row named for its destination; exactly one `AXRow` selected and it follows the destination (Leaderboards, Item Shop, Statistics) |
| Songs list \| detail | One song row reports selected; tree order sidebar → list → detail; the detail has headings |
| Every destination (Songs, Leaderboards, Statistics, Suggestions, Rivals, Compete, Item Shop) | No unnamed button, image, field or control; no image repeating the next element's name; headings present (Item Shop: none expected) |
| Toolbar | Every item labelled and tooltipped, labels unique; Songs' field placeholder "Filter Songs" |
| Charts | No mark named by its plotted range ("0 to 1"): rank-history bars read their date, with "Rank N of M, total score …" as value |
| Song detail | The song title is the detail's first heading (`fst.song-detail.hero-title`) |

Fixed (before → after): rank-history bars read "0 to 1", "1 to 2" … and the line and point marks repeated them → one element per bar named by its date (line and points hidden); the song detail's hero (title, artist, year) had no heading trait → heading. Leaderboards read 9 decorative instrument images before their headings (fade-in un-hiding, rule above; app-wide on iOS 18+ too) → 0; the footer's Deselect button now says "Deselect Profile"; with a player, the profile toolbar item had an empty label (the monogram was the whole label) → "Profile: <name>"; two toolbar items were named "Search" (global search and Songs' system filter field) → the global one is "Search Festival", as in Edit › Search Festival….

Unverifiable in the hosted tree (check with VoiceOver): non-link stat tiles are `AXUnknown` and the walker reads no `AXValue` for them, nor for chart bars, although both set `accessibilityValue`. Still needs VoiceOver and Full Keyboard Access with Automation Mode (or a person): spoken order and phrasing in the live window, VoiceOver cursor and keyboard focus after navigation (row → detail, sheet dismissal), rotor contents, Tab loop through sidebar → list → detail → toolbar, focus rings on rows (`festivalRowButtonStyle`), sheets (Filter, Profile, Search, Notifications, What's New are window sheets the hosted window never presents), the Settings window and menu-bar commands through accessibility.
