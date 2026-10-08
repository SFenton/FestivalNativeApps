# Apple accessibility audits

> **What:** audit rules, rendered-contrast checks and the currently open Apple audit findings. **Read when:** writing the accessibility test every Apple UI change ships with ([strategy](../strategy.md#accessibility-tests-with-every-change)), the whole-app audit phase, or a change touching text over artwork, the tab edge or large text.

## Rules

- Run XCTest `performAccessibilityAudit` (`.all`). No blanket waivers and never a whole audit type; keep failing crops/xcresults as private evidence.
- iPhone's only scoped exception: iOS 26.5 Songs "Retry Item Shop status" may report ≤1 contrast and ≤1 Dynamic Type issue for that exact identifier/label, **after** the test independently proves ≥4.5:1 rendered text (measured 18.72:1) and >1.35× AX5 glyph growth. Never extend it.
- iPad accepts an issue only through an entry in [iPad audit waivers](#ipad-audit-waivers): a measurement of that issue in the same run, or a system control we do not own. Add an entry there and in `IPadAuditWaivers.swift` together, with its evidence.
- Named visible text gets a rendered-pixel contrast assertion (≥4.5:1 text, ≥3:1 meaningful edges) from the app screenshot — token math (`tools.contrast_gate`) is not rendered evidence.
- Large text: assert real glyph growth (>1.35× at AX5) and that actions remain reachable above native chrome in portrait and landscape.
- macOS-hosted large-text checks: HIG Typography, "macOS doesn't support Dynamic Type", so on the `swift test` host a text style or `@ScaledMetric` renders the same at AX5 as at Large. A hosted test of a container (gate, sheet, row shell) proves growth with fixture text that reads `dynamicTypeSize` where it is drawn and applies the HIG iOS size table (`ReloadGateA11yText`), then measures rendered ink height (> 1.35×) and the height the text needs at its width; a clamp or clip in the container fails both. Real text-style growth of a page needs an iOS run (`SongsUITestSupport.brightGlyphHeight`).
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

## Drawer journey (iPhone and iPhone Duo)

`DrawerAccessibilityJourneyTests` (#396) audits the open navigation drawer with `.all` and never drops a whole audit type. It applies the iPad lane's evidence rules within the same run:
- **Named drawer element, contrast:** accepted when its rendered text in the app screenshot is ≥ 4.5:1 (`contrast-rendered`). The audit misjudges every white row on the dark glass.
- **Page element under the drawer, contrast:** accepted when it is absent from `app.snapshot()` (`behind-modal-drawer`). This counts only when that snapshot holds the drawer's own rows.
- **No element (iPhone Duo), contrast:** accepted when every static text in the panel renders ≥ 4.5:1 (`unattributed-contrast-page-floor`).
- **Unattributed "may be clipped at larger sizes" prediction:** accepted only when the drawer relaunched at AX5 audits clean for clipping.

`app.debugDescription` still prints SwiftUI views hidden with `accessibilityHidden`, such as the page under the drawer. Assert hiding against `app.snapshot()`, never the debug description. On the iPhone Duo simulator, `app.snapshot()` stops after about 11 nodes (depth 6), short of the drawer, and comes back empty after an audit. Before using a snapshot as evidence, check that it reaches the region under test. Element queries still work there. The Duo drawer's modality is proved by `DuoDrawerJourneyTests` (`isModal`).

Allow one pixel of tolerance on target sizes. A fixed 44 pt control reports 43.67 pt (131 px at 3×) when layout lands it off the pixel grid.

## iPadOS and iPhone Duo audit journeys

`apple/Apps/iPadOSUITests/IPadAccessibilityAuditTests.swift` (FST Native iPad Pro 11" and iPhone Duo (FST), fixture service) audits every page and sheet, collects every issue per page and writes `<mode>-<group>.json` plus each page's upright capture (`.png`) and element tree (`.tree.txt`) to `FST_AUDIT_OUT` (pass `TEST_RUNNER_FST_AUDIT_OUT=<dir>` to `ios_sim.py uitest`; `FST_UITEST_KEEP_RESULTS=1` keeps a green batch's `.xcresult`). Groups: **browse** (Songs, Song Detail, Sort, Filter, Paths, Item Shop, Search), **rankings** (Leaderboards, Full Rankings, Player, Settings, Licenses, profile selection, What's New), **profile** (Statistics, Suggestions, Rivals, Rival Detail, Bands, Notifications), **shell** (the overlay flyout open with a player; and, in a window that splits, each split page with its trailing pane open: Song Detail → Lead board, Song Detail → score history, Rivals → Rival Detail, Leaderboards → player, Full Rankings → player, Settings → Licenses; JSON `skipped` lists split pages a portrait or compact window leaves out). An issue passes only through a waiver below; everything else fails the method.

| Mode (test prefix) | Window | Audit types |
|---|---|---|
| `Landscape` (was `ThreeColumn`) | Landscape full screen (1210 pt): flyout shell, on-demand split | All |
| `LandscapeAX5` | Landscape, AX5 (shell group: the flyout footer and the split panes at the largest size) | All but contrast |
| `Regular` | Portrait full screen (834 pt, regular): flyout shell, one stack (no split) | All |
| `Compact` | Portrait ⅓ tile ("Arrange thirds", 375 pt): phone tabs and drawer | All |
| `AX1`, `AX5`, `AX5Compact` | Portrait, `-UIPreferredContentSizeCategoryName` | All but contrast |
| `BoldText`, `IncreaseContrast`, `ReduceTransparency` | Portrait; skip unless the runner sees the setting: `ios_sim.py uitest --device ipad --a11y bold-text\|increase-contrast\|reduce-transparency` | Bold Text: all but contrast; others: all |
| `Duo`, `DuoAX5` | iPhone Duo in the pose Device Hub holds (`ios_sim.py pose --set unfolded`, `… --set rotate-right` for inner portrait, `… --set folded`), run with `uitest --device duo --app ipad`; the test never rotates or resizes the Duo, reads the window once (inner landscape 951 pt splits) and turns the capture upright from the window's aspect | Duo: all; DuoAX5: all but contrast |

```bash
TEST_RUNNER_FST_AUDIT_OUT=/tmp/audit python3 tools/ios_sim.py uitest --device ipad --batch-size 1 --timeout 2400 \
  --only IPadAccessibilityAuditTests/testRegularBrowse   # one group ≈ 15–40 min (second launch per page for Dynamic Type evidence)
```

Re-check single pages with `TEST_RUNNER_FST_AUDIT_PAGES=song-detail,player` (page names as in the JSON; the JSON's `pages` records the filter, so a filtered run never stands in for a full group). `ios_sim.py drive … --steps "…; audit:/tmp/a.txt"` audits whatever state a script reaches.

- **Where text is measured** (`IPadAuditPageEvidence.ContentArea`): the window minus the bottom bars and, per column, below each top navigation bar (+8 pt scroll-edge effect) and above each pager (`*.pager`, −44 pt fade). A split has a bar per pane; text under one is scrolled clear first (Song Detail's card header under the leading bar read 1.84:1, the board's last rows over its pager fade 2.6–3.7:1). A bar's own titles and buttons count as measurable.
- **Captures.** `XCUIScreen.main.screenshot()`, not `XCUIApplication.screenshot()`: it covers the whole screen, so element frames (screen points) map directly, including a ⅓ window away from the origin. In landscape it arrives in portrait framebuffer orientation and is rotated upright (`IPadAuditRenderedContrast.Capture`); the app screenshot was the one cut off. Points come from the bitmap and its scale: SpringBoard's frame (1194 pt) is shorter than the 11-inch framebuffer (1210 pt).
- **Rendered contrast** (`IPadAuditPageEvidence.reading`): each recognized word (Vision) of the element's own label is measured on its own box: surface = median pixel, text = upper quartile of the pixels ≥ 1.5× away from it (the glyph core); the weakest word is the reading. Element frames alone mislead: a selected sidebar row's symbol (recognized as "0Ol") read the row at 3.6:1 instead of 13.8:1, a fixed top percentile read a 296 pt "Settings" row at 2.8:1 instead of 17:1, the glyph median read 11 pt pill text at 4.3:1 where its colours give 6:1. Elements under the tab bar, the floating page tools or the screen edge are scrolled clear with slow drags first.
- **Unattributed issues.** On iPadOS 26.5 the audit reports many SwiftUI text nodes with **no element** ("Contrast failed for SwiftUI.AccessibilityNode"; the issue's own element reference is nil, also in its private ivars). They get page-level evidence (`IPadAuditPageEvidence`): every static text in the region is measured, and every recognized line in the region must name an element.
- **Dynamic Type heuristics** (`IPadAuditTextEvidence`): for "partially unsupported" and "Text clipped" the page is launched again at AX5 (at the default size when the audit ran at AX5), the same element (identifier and label, or label and type, case-insensitive, by reading-order ordinal) is found, its text growth measured on recognized word heights (a 44 pt minimum row hides glyph growth in frame heights) and, for clipping, its text read back from the AX5 capture.

### Shell structure

`apple/Apps/iPadOSUITests/IPadShellAccessibilityTests.swift` (replaces `testThreeColumnReadingOrderAndTraits`, which checked the retired sidebar \| list \| detail order). XCUITest cannot read VoiceOver focus, so the app runs with `FST_DEBUG_A11Y_FOCUS_TRACE=1` and shows its last focus move as the element `fst.nav.a11y-focus` (`App/Layout/AccessibilityFocusMove.swift`: the element handed to `screenChanged`/`layoutChanged`, or the row whose SwiftUI `accessibilityFocused` was set).

| Journey | Asserts |
|---|---|
| `testFlyoutIsModalAndReturnsFocus` (landscape) | Open: focus on "Festival Score Tracker" (the panel's heading); the page behind leaves the accessibility tree (no `fst.songs.*`, `isModal`); Close and a scrim tap each close it and focus returns to `fst.shell.drawer.open` ("Open Navigation") |
| `testFlyoutFooterReachableAtAX5` (portrait, landscape) | At AX5 the footer (profile, Deselect Profile, Settings) scrolls with the rows and each item comes wholly on screen and hittable |
| `testSplitReadingOrderSelectionAndFocus` (landscape) | Full Rankings, Rivals, Leaderboards, Song Detail (Lead board), Settings (Licenses): starts full width; the opened row reads before `fst.split.trailing` and only the opened item's rows are selected (Leaderboards lists the same player on every card, Full Rankings in the selected-profile footer too); the trailing pane starts at the midpoint; focus moves to the pane's top heading and that heading is in the pane; Close returns to full width, clears the selection and focus returns to the row (`row: player:…`). JSON `split-structure.json` |

Heading traits are read from the snapshot's `traits` (readable on iPadOS 26.5).

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
| `behind-modal-drawer` | b | Contrast | An element under the open flyout/drawer panel (`fst.shell.drawer`) | This run measures it absent from `app.snapshot()` (what VoiceOver reads; the panel is modal, `IPadShellAccessibilityTests` asserts the page leaves the tree) and the panel covers it (measured 1:1, no glyph pixels). The drawer's own rows are measured as usual. Added Lane A11Y3 |
| `description-outside-tree` | b | Sufficient description | An unlabelled `image` | This run measures it absent from `app.snapshot()` (hidden decoration the audit still enumerates). Added Lane A11Y3. Song Detail's full-screen cover `Image`, which stayed in the snapshot, is gone: the cover is drawn in a Canvas (Lane A11Y4) |
| `system-search-placeholder-contrast` | c | Contrast | `searchField` | UIKit draws the placeholder in `placeholderText` ("nearly passed"; "Filter Songs" core 5.6:1). HIG Search fields: use the system field. iPhone accepts the same issue (#92) |
| `system-search-placeholder-clipped` | c | Text clipped | `searchField` | A search field's placeholder is single-line by construction (global search's "Search songs or players" at AX5) |
| `system-bar-title-size` | c | Dynamic Type ("partially unsupported") | Static text inside a top navigation bar (pseudo-container `system-navigation-bar`, the union of the panes' bars) | UIKit caps the text size of what a bar hosts: Song Detail's pinned title (shown once the hero scrolls away) measured 1.1× at AX5 in the split's leading bar. It offers the Large Content Viewer (`accessibilityShowsLargeContentViewer`), as system bar titles do, and the hero title it repeats grows in full. Added Lane A11Y3 |
| `system-search-clear-button` | c | Hit region | Button labelled "Clear text" | UISearchBar's 20.5 pt clear button; the field is the target |
| `system-toolbar-badge` | c | Contrast | Static text inside `fst.shell.notifications` | iOS 26 system toolbar-item badge (white on system red, ≈ 4:1 by the system colours); hidden from VoiceOver, the bell says "N unread". Left out of the page contrast floor |
| `system-keyboard-candidates` | c | Sufficient description | `other` inside the system keyboard | Empty QuickType candidate cells while the compact Search field is focused |
| (not audited) | c | – | Paths' "Some Instruments Unavailable" system alert | UIKit alert; the journey taps OK and audits the Paths sheet itself |

### Results (Lane A11Y4, 2026-10-06)

Closes Lane A11Y3's open items (`6fa6f7d4`…). Raw → open; a cell marked *pages* re-ran only the affected pages (`FST_AUDIT_PAGES`: Song Detail, Player, Settings, Statistics, Rival Detail and the shell pages); the A11Y3 table below holds every other cell.

| Device · mode | Browse | Rankings | Profile | Shell | Structure |
|---|---|---|---|---|---|
| Duo · inner landscape (951 × 669) | 6 → 0 | 9 → 0 | 32 → 0 | 33 → 0; AX5 4 → 0 | flyout (Close + scrim) ✓, splits 5/5 ✓ |
| Duo · inner portrait (669 × 951) | 0 → 0 | 16 → 0 | 34 → 0 | 0 → 0 | flyout ✓ |
| Duo · folded (466 × 678) | 17 → 0 | 30 → 0 | 69 → 0 | 12 → 0 | flyout ✓ |
| iPad · Landscape (*pages*) | 22 → 0 | 25 → 0 | 56 → 0 | 205 → 0 (Song board split re-run 40 → 0); AX5 25 → 0 | `IPadShellAccessibilityTests` 4/4 ✓ |
| iPad · Regular / Compact ⅓ / AX5 (*pages*) | 30 → 0 / 29 → 0 / – | 50 → 0 / 38 → 0 (Settings re-run 17 → 0) / 5 → 0 | 95 → 0 / 73 → 0 (Statistics by route 25 → 0; AX5 ⅓ 4 → 0) / 17 → 0 | – | |
| iPad · Increase Contrast (*pages*) | 16 → 0 | 29 → 0 | 67 → 0 | – | |

Every Duo page is reached in every pose (Search, Statistics, What's New included), and the Duo cells are full groups. **The iPad and Duo audit journeys are green.**

- **Song Detail's unlabelled full-screen `Image`** (every mode's tree; Increase Contrast "Element has no description") was the song cover the backdrop draws with `scaledToFill` ({-188, 0, 1210, 1210} on an 834 pt window). It stayed in the tree with the backdrop, its canvas and the image all `accessibilityHidden(true)`, and with the fade-in hiding switched off (measured by drive, `FST_EXP_HIDDEN`), so the cover is drawn in a `Canvas`, which exposes no element (`CoverLayerView`). Separately, `PublicationRefreshBoundary` wrapped every pushed page in `.accessibilityHidden(!showsContent)` (= `false` once shown) → `.accessibilityHidden(while:)`, and `AccessibilityHiddenSourceTests` rejects a computed `accessibilityHidden(_:)` argument on views.
- **Landscape Settings split** ("Potentially inaccessible element/text"): `.accessibilityElement(children: .combine)` around the Licenses list-detail link merged the button with the selection fill and accent bar into a selected *static text* and left the inner button exposed → the link is labelled directly (a selected button "View Licenses").
- **Rank History bar hit area** (Duo inner portrait, 18.8 pt): the chart is one adjustable element over the plot (HIG Charts: "consider making the whole plot area the hit target"); its value reads each visible snapshot ("9/26/26: Rank 12, total score 1,000; …") and swiping up/down pages like the pager buttons.
- **⅓ Rival Detail's last "View All"**: reached and measured (compact profile 73 → 0); its scroll view ends above the page tools (scroll bar 86–1077 pt, tools from 1077 pt), so it scrolls clear.
- **Duo reach** (`IPadAccessibilityAuditTests.screenOrigin`): `app.coordinate` gestures never land on the inner display, a coordinate taken from the app window does; drags start left of the ≈ 80 pt vertical bar (one starting on it pressed its tab buttons). That fixed the scrim tap and the AX5 comparison scrolls (Filter, Suggestions, Search hint now have evidence). Search opens with `FST_DEBUG_TAB=search`; Statistics and the split journey's Leaderboards open by route (with a profile the tab launch resolves against the compact set and shows Songs); What's New is proved by Close (beside the vertical bar it has no Dismiss bar, `/duo` M1).
- **Measured in place**: a list header whose frame starts in a bar's 8 pt scroll-edge band but whose recognized label lies wholly below it (folded Notifications "New", the split's Song Leaderboard header) is measured where it is (`IPadAuditPageEvidence.labelDrawnInside`); such a header cannot scroll further down. Page evidence names any text left unmeasured (`unmeasured`).
- **⅓ Statistics** opens by route (`Page.compactEnv`): the tab launch fell back to Compete in a ⅓ window, which earlier compact runs recorded as "statistics".

### Results (post-redesign, Lane A11Y3, 2026-10-05)

Raw audit issues → issues left open after the waivers, per group (browse / rankings / profile / shell), on the Lane SPLIT shell (overlay flyout, on-demand split). Each cell is the latest run after the fixes below (JSON `window` proves the window or Duo pose). Lane A11Y2's pre-redesign counts are in git history (`6cec85b4`…`b05dc5d9`).

| Device · mode | Browse | Rankings | Profile | Shell (flyout + splits) | Left open |
|---|---|---|---|---|---|
| iPad · Landscape (1210 pt, splits) | 41 → 0 | 54 → 0 | 102 → 0 | 217 → 2 | Settings split: 2 unattributed element-detection issues (below) |
| iPad · Landscape AX5 | – | – | – | 25 → 0 | – |
| iPad · Regular (portrait 834 pt) | 43 → 0 | 116 → 0 | 165 → 0 | 12 → 0 | – |
| iPad · Compact ⅓ (375 pt) | 47 → 0 | 86 → 0 | 168 → 1 | 16 → 0 | Rival Detail's last "See All" not measured (below) |
| iPad · AX1 | 7 → 0 | 10 → 0 | 48 → 0 | 0 → 0 | – |
| iPad · AX5 | 4 → 0 | 5 → 0 | 31 → 0 | 0 → 0 | – |
| iPad · Bold Text | 15 → 0 | 44 → 0 | 68 → 0 | 1 → 0 | – |
| iPad · Increase Contrast | 25 → 1 | 79 → 0 | 116 → 0 | 11 → 0 | Song Detail: unlabelled full-screen Image node in the tree (below) |
| iPad · Reduce Transparency | 16 → 0 | 44 → 0 | 73 → 0 | 12 → 0 | – |
| Duo · inner landscape (951 × 669, splits at the hinge) | 6 → 2, Search unreached | 9 → 0, What's New unreached | 29 → 2, Statistics unreached | 30 → 0 | Filter sheet and Suggestions: 4 Dynamic Type issues without comparison evidence (below) |
| Duo · inner landscape AX5 | – | – | – | 4 → 0 | – |
| Duo · inner portrait (669 × 951) | 1 → 1 | 17 → 1 | 30 → 3, Statistics unreached | 0 → 0 | Song Detail Image (as iPad); Player: a Rank History bar 18.8 pt "Hit area is too small"; Suggestions: 3 Dynamic Type issues without comparison evidence |
| Duo · folded (outer 466 × 678) | 23 → 2 | 30 → 0, What's New unreached | 73 → 1 | 12 → 0 | Song Detail Image; Search hint "Text clipped" without comparison evidence; Notifications "New" header unmeasured |

**iPhone Duo** (`Duo*` modes, `uitest --device duo --app ipad --pose … --set-pose [--rotate right]`; JSON `window` proves each pose). On the inner display the split's leading pane ends at the hinge and its rows, Close (in the vertical bar) and the trailing pane audit clean; the rail's items (Close, Search, More, tabs) are named. The structure journey passes on four of five split pages there (focus moves into the pane — to its first content heading, since the pane's title sits in the vertical bar — and back to the row; Leaderboards' row was not reached), and the drawer returns focus to the rail's **More** button when Open Navigation has overflowed into it (fixed). `XCUIApplication.screenshot()` is black there. A11Y3's unreached pages and coordinate gestures are resolved by Lane A11Y4 (above).

Split pages are audited open only in the landscape modes (portrait and compact push them; JSON `skipped`). Structure journeys (iPad, landscape and portrait): `IPadShellAccessibilityTests` 5/5 pass — flyout modal with focus in and out, drawer modal in a ⅓ window, AX5 footer reachable, all five split pages ordered leading → trailing with focus to the pane title and back to the row.

Fixed (Lane A11Y3; shared Swift reaches iPhone too): **Score History chart** — its bars were exposed by plotted range ("0 to 0.2") and, being selectable, audited as 11–19 pt controls in an AX5 Duo pane → one element (label, summary value; the rows read every score); **split focus** — opening a split's trailing pane moves VoiceOver focus to the pane's title, closing it returns focus to the row that opened it; opening the flyout focuses its title and dismissing it returns focus to Open Navigation (`AccessibilityFocusMove.swift`; HIG VoiceOver "Inform VoiceOver of visible content or layout changes"); **drawer modality** — behind the phone drawer (⅓ window, iPhone) the page stayed in the tree under the panel's `isModal` (covered rows measured 1:1) → the shell is hidden while the drawer is open; **Swift Charts tick labels** (A11Y2's open Statistics item: 3 unattributed "Potentially inaccessible text" on Player/Statistics in landscape, 2 in portrait, 3 on Song Detail's score history) → one static-text element per axis over its labels, reading its range ("Rank scale, #3 to #15"; `ChartAxisAccessibility.swift`), outside the chart's own identifier and adjustable action (inside it they were audited as 18 pt controls); **split selection** — the open row's translucent accent fill sat over its text and washed the rivals pills to 4.0–4.3:1 → drawn behind the row; **prominent buttons** — white on the accent fill measured 3.86:1 ("Start New Mix") → `AccentText.prominentFill` (≈ 5.2:1) on default-tint prominent buttons; accent-tinted text buttons (fixture "Check Publication" 3.6:1, Song Detail's "Retry … scores") → `AccentText.blue`; **AX5** — Song Detail hung the main thread in a lazy-grid layout loop when scrolled to its end in portrait (sampled; hit twice by the AX5 comparison launches) → eager card rows at accessibility sizes; the score-history accuracy pill (fixed 76 × 24 pt) cut "95.5%" to "9…" → grows at accessibility sizes; the Rank History summary cut "Total Score 89,400,000" → wraps; stat tiles in a 375 pt window stacked "SONGS PLAYED" a letter per line and cut "2 (66.6%)" to "(…" → one column at accessibility sizes (`StatGridColumns.accessibilityMinimumColumns`), and the AX5 chevron sat on the value → scaled side padding; Song Detail's pinned bar title offers the Large Content Viewer. A11Y2's open items: Statistics tick labels fixed (above); compact Song Detail "No scores recorded yet" and Statistics "88,000,000" now measured (compact profile 0 open); Player "2 (66.6%)" fixed (above); Rival Detail reached in every mode.

Audit tooling (no app change): per-pane bar edges and pager fades in the measurable area; the AX5 comparison scrolls where the audited element was (a split's middle is its divider) and up to sixteen drags; one- and two-letter labels compare frame heights ("vs": 24 → 48 pt read 1.2× from Vision's boxes); Song Detail split pages open the song from its row (a page pushed by `FST_DEBUG_SONG` did not scroll under XCUITest); iPhone Duo captures the screen that shows the app (`XCUIScreen.main` is the black outer panel while the app runs inside) and turns it upright by recognition confidence; `ios_sim.py uitest --pose P --set-pose [--rotate right]` holds the Duo pose inside each batch's lock hold.

Open (not waived): A11Y3's Duo hit area, Song Detail Image, Settings split and ⅓ "View All" items are closed (Lane A11Y4, above). The rest of the iPad open list is unchanged: Full Keyboard Access and hardware-keyboard focus ([ipados.md](../../design/apple/ipados.md)); spoken VoiceOver confirmation of the focus moves (operator script, [voiceover.md](voiceover.md)); the shared Song row's mid-word breaks at AX5 in a ⅓ window (iPhone-owned). Tooling: the browse/rankings/profile cells of Landscape, AX5, Bold Text and Reduce Transparency predate the button-text page floor (2026-10-05 22:44) and measured static text only; every shell cell and the Regular, Compact, AX1 profile and Increase Contrast runs came after it.

## macOS without Automation Mode

Automation Mode is not authorised on this Mac ([macos host limits](../../platforms/apple/macos.md)), so macOS accessibility evidence is in-process: `apple/Tests/FestivalUITests/MacAccessibilityTreeTests.swift` hosts the real `MacRootView` over the loopback fixture service (`RivalsMockService`) and walks the AppKit accessibility tree (`macAccessibilityTree`: role, subrole, label/title/value, identifier, selected, `isAccessibilityElement`). Toolbar items come from an `NSHostingController` with `sceneBridgingOptions = [.toolbars, .title]` in a titled offscreen window ([hosted snapshots](hosted-snapshots.md)). `FST_MAC_AX_OUT=<dir>` writes tree dumps.

| Check | Result |
|---|---|
| Sidebar | `AXOutline` "Sidebar"; every row named for its destination; exactly one `AXRow` selected and it follows the destination (Leaderboards, Item Shop, Statistics) |
| Songs list \| detail | One song row reports selected; tree order sidebar → list → detail; the detail has headings |
| Every destination (Songs, Leaderboards, Statistics, Suggestions, Rivals, Compete, Item Shop) | No unnamed button, image, field or control; no image repeating the next element's name; headings present (Item Shop: none expected) |
| Item Shop list rows (#397) | `ShopRowAccessibilityTests` (fixture offers, compact list): matched rows `AXButton` "title, artist · year, New/Leaving Tomorrow"; display-only offer `AXStaticText` at standard and AX5 sizes; bags `AXLink` "<title>, Open Official Item Shop", read right after their row, ≥ 44 × 44 pt; at AX5 rows wrap and bags span the row beneath it |
| What's New sheet (#80, backfilled by #434) | `WhatsNewAccessibilityTests`: store/TestFlight/development installs read version or tester heading → category `AXHeading` → its bullets (page order, "•" hidden) → Dismiss; frames follow reading order; pending spinner `AXBusyIndicator` "Getting notes for this install"; Duo vertical bar reads the same notes without Dismiss; Dismiss full-width bottom bar outside the list (element ≥ 44 pt, macOS button ≥ 28 pt); long notes/headings wrap in a narrow column (layout only: macOS keeps the font size, so this is not AX5 evidence). **AX5** is proved on iPhone and iPad by the XCUITest `WhatsNewAccessibilityJourneyTests` (`ios_sim.py uitest --only WhatsNewAccessibilityJourneyTests`, fixture document `FST_DEBUG_WHATS_NEW_FILE`, mock service): default vs AX5 launches, every heading and bullet revealed between the bars, recognized line height > 1.35× and read back whole, headings keep the header trait in order, scoped audit (Dynamic Type, clipped text, hit region, description) clean, Close and Dismiss hittable, Dismiss ≥ 44 pt and closes; iPhone portrait (portrait-only app), iPad portrait and landscape |
| Load and reload gate (#71, backfilled by #431) | `ReloadGateAccessibilityTests` (fixture page around `FestivalReloadGate`, plus Item Shop's List → Grid switch): one `AXBusyIndicator` named for the load ("Loading leaderboard", "Loading Item Shop") with its identifier, reachable through `accessibilityChildren`, and nothing unnamed; no stale rows beside it; the selectors above stay named, selected and pressable; the retained header stays an `AXHeading` and reads before the spinner; rows read top to bottom after the selectors; same at AX5; selectors ≥ 44 × 44 pt and wholly on the page while loading, reloading and shown, at standard and AX5 sizes; at AX5 the selector, header and row glyphs render > 1.35× their Large height (rows inside the gate as tall as the selectors outside it), every text has the height it needs at its width and lies on the page, and pressing each selector during the AX5 reload selects it behind the named spinner; Reduce Motion (system or in-app) still holds the spinner ≥ 400 ms |
| Toolbar | Every item labelled and tooltipped, labels unique; Songs' field placeholder "Filter Songs" |
| Charts | No mark named by its plotted range ("0 to 1"): the rank-history chart is one adjustable element ("Lead rank history chart") whose value reads each visible snapshot's date, rank and total score (per-bar elements until Lane A11Y4) |
| Song detail | The song title is the detail's first heading (`fst.song-detail.hero-title`) |
| Fixed-divider split (Lane A11Y3) | Full Rankings, Leaderboards and Rivals with an item open: sidebar → list → trailing pane, only the opened item's rows selected (Leaderboards lists the same player once per card), divider decorative, nothing unnamed; the window toolbar names Close ("Close (Esc)", unique labels). `macTreeSplitPagesReadLeadingThenTrailing`, `macTreeSplitToolbarNamesClose` |

Fixed (before → after): rank-history bars read "0 to 1", "1 to 2" … and the line and point marks repeated them → one element per bar named by its date (line and points hidden); the song detail's hero (title, artist, year) had no heading trait → heading. Leaderboards read 9 decorative instrument images before their headings (fade-in un-hiding, rule above; app-wide on iOS 18+ too) → 0; the footer's Deselect button now says "Deselect Profile"; a display-only Item Shop row was `AXUnknown` at standard sizes (`MarqueeText`'s `children: .ignore` dropped its `Text` role) → `MarqueeText` adds `.isStaticText`, so every marquee is static text in every branch (#397); every loading spinner (`FestivalLoadingView`) was a role-less `AXUnknown` element named "Loading …" with the system indicator hidden beneath it, and a retained header (song leaderboard, song band leaderboard) read after the reload spinner → the `ProgressView` itself carries the name (one `AXBusyIndicator`), and the gate's retained frame reads first (#431); with a player, the profile toolbar item had an empty label (the monogram was the whole label) → "Profile: <name>"; two toolbar items were named "Search" (global search and Songs' system filter field) → the global one is "Search Festival", as in Edit › Search Festival….

Unverifiable in the hosted tree (check with VoiceOver): non-link stat tiles are `AXUnknown` and the walker reads no `AXValue` for them, nor for chart bars, although both set `accessibilityValue`. Still needs VoiceOver and Full Keyboard Access with Automation Mode (or a person): spoken order and phrasing in the live window, VoiceOver cursor and keyboard focus after navigation (row → detail, sheet dismissal), rotor contents, Tab loop through sidebar → list → detail → toolbar, focus rings on rows (`festivalRowButtonStyle`), sheets (Filter, Profile, Search, Notifications, What's New are window sheets the hosted window never presents), the Settings window and menu-bar commands through accessibility.
