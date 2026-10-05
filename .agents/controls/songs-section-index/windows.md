# Songs section index — Windows notes

> **What:** the Windows Jump button and `SemanticZoom` letter grid that stand in for the right-edge index. **Read when:** changing `JumpButton`, the zoomed-out `JumpIndex` grid or `SongSectionHeader` in `Pages/SongsPage.xaml(.cs)`. Behavior: [spec.md](spec.md). Page context: [songs/windows.md](../../pages/songs/windows.md).

## Design

- A **Jump** toolbar `Button` (`fst.songs.section-index-button`, name "Jump to Section", list glyph; label collapses below 640 epx page width) zooms the `SemanticZoom` out to a centred `GridView` of section labels (`fst.songs.section-index`, name "Jump to section"). Picking a label zooms back in with that section's title pinned in the bar and its first row under it (`SongSectionHeader.JumpPinDelta`). Ctrl+Minus from the list also opens it.
- `winui-design`: `winapp find-ui "semantic zoom jump to group"` returns the WinUI Gallery `SemanticZoom` sample (grouped `ListView` zoomed in, a list over `CollectionGroups` zoomed out). That is this structure, and it keeps the platform list's virtualization instead of a custom scrubber. "Prefer platform controls; build custom UI only when no control fits."

## States and reachability

| Spec state | Windows | Evidence |
|---|---|---|
| `hidden` | Jump collapses for no rows, one unlabeled section (Item Shop sort with one bucket, player metric sorts) and Year | `songs-search` (No Results), `songs-sort-shop` one bucket, `songs-sort` Year |
| `title` | Jump shown; the grid lists `#`, `A`–`Z` present in the list | `songs-jump` |
| `artist` | Same, over artist initials | `songs-sort` (Artist ↓ → open → Esc) |
| `year` | **Not reachable**: Year groups by decade with no quick-jump (operator 2026-09-28), so Jump hides | `songs-sort` |
| `scrubbing` | The zoomed-out grid is open; arrows move between labels, Enter/click picks | `songs-jump`, `a11y.json` `songs-jump` |

Duration and Item Shop sorts also show Jump over their buckets ("Under 1 Minute" …, Shop sections) because Windows merges Quick Links into Jump ([quick-links/windows.md](../quick-links/windows.md)); the spec's Title/Artist/Year-only rule is the scrubber's, not the zoom's.

## Fixes from the issue #231 validation (2026-10)

- **Focus on open:** Jump left keyboard focus on the button, so Narrator said nothing about the grid and a keyboard user needed a Tab to reach it. `FocusCurrentLetter` now focuses the label of the section the bar names (`stickySection`), with a focus rectangle unless a pointer opened it. This also clears the two Axe ToolTip-host errors `songs-jump` used to report (UIA Invoke no longer leaves the button's ToolTip open).
- **Escape from the button:** Escape closed the grid only while focus was inside the zoom. The handler is now on the page's `PreviewKeyDown`, so Escape closes it from Jump or the toolbar too; focus returns to Jump.
- **Heading after a pick:** after picking I or M at 300% scale, layout rounding left the picked title 0.1–0.5 epx short of its pinned place, so `SongSectionHeader.Push` kept the previous letter current. The UIA heading `fst.songs.section-header` read "H" while the bar showed "I". `Push` now treats a title within `PinSlack` (0.5 epx) of its place as pinned. That is below one epx, so the #288 push still hands off without a step (`Push_PositionsFollowTheTitleContinuously` passes).
- **Show/hide motion:** Jump appeared and vanished abruptly as sort or results changed, against the spec. It now uses `FadeIn.OnShow` (400 ms fade-up) and the new `FadeIn.OnHide`, a composition implicit hide fade of 167 ms (`FadeInTiming.HideDuration`, WinUI `ControlFastAnimationDuration`). Both are off under Reduce Motion or Windows animation effects off (`Motion.Allowed`).
- **Long labels:** `ItemsWrapGrid` sizes every cell from the first item, so the Item Shop grid truncated "Leaving Tomorrow" and "Not In Shop" to "Leavi…" / "Not I…" (the old `windows-accessibility.md` note). `SizeJumpCells` measures each label in `SubtitleTextBlockStyle` and sets `ItemWidth` from `SongSectionHeader.JumpCellWidth`: the widest label plus padding, at least the 72-epx letter cell and at most the grid width. Letters keep 72-epx cells; Duration and Shop labels show in full (2 columns at compact).
## Configurations checked (issue #231)

| Configuration | Result |
|---|---|
| Compact 500 / medium 900 / wide 1280 epx, live service (731 songs) | Pass: Title, Artist, Duration and Shop grids open, pick lands on the section, bar and UIA heading agree (after the fix) |
| Maximized, snapped left | Pass: Title grid 13 columns maximized, Artist grid 8 columns snapped (Jump collapses to its glyph); the current label is focused |
| Dark (app is Dark-only) / light system theme | Same rendering by design (`RequestedTheme="Dark"`, songs/windows.md deviation) |
| High contrast Desert, Night Sky | Pass: labels and focus rectangle use system colours; Axe 0 errors |
| Text 200% | Pass: labels and Jump label grow; Axe 0 errors |
| Display 100% / 150% | Pass at all three sizes; Axe 0 errors |
| Keyboard | Pass: Jump (Enter) → focused label → arrows → Enter → first row focused; Esc from the grid or from Jump returns to Jump; Ctrl+Minus from a row opens the grid with a label focused |
| Narrator / UIA | Labels are `ListItem`s named by their text with Invoke; the grid is `List` "Jump to section"; the bar is a Level 2 heading naming the current section |

## Far scrolls and the pinned header (issue #248, 2026-10)

- **Jump itself passed** on the live catalogue (731 songs) at compact, medium and wide: picks # → P, P → B (after scrolling to S), V, A, Q, Y, M, # and Z all land with the section's first row under the bar, and the bar and the UIA heading name it. Z shows Y because the list bottoms out, which is correct.
- **Bug: stale header after a far scroll without Jump.** If you drag the scrollbar thumb or scroll by UIA `SetScrollPercent` (Narrator or other assistive tech), the last `ViewChanged` comes before `ItemsStackPanel` realizes rows at the new offset. The rows still realized are far above the viewport, so geometry found no row in view and the stale `FirstVisibleIndex` (0) kept "#" over S or F songs indefinitely. Nothing re-read the header after layout. Jump was unaffected because its settle step already re-checks after layout. The bug reproduced live (74% left "#" over "Say It Proud") and with `--large-catalogue` at 30, 50, 74 and 88%.
- **Fix:** `SongSectionHeader.TryFirstVisibleRow` reports when no realized row is in view. `UpdateStickyHeader` then uses the fallback for one frame and re-reads after the next `LayoutUpdated` (`RecheckHeaderAfterLayout`). That is a one-shot handler, skipped while the grid is zoomed out, and bounded to 4 consecutive passes, so a steady list costs nothing.
- **Configurations (#248, live service, fixed build).** The pages are in `a11y-section-index.json`. index-open checks focus on the first label and the Esc return. index-far-jumps checks # → P, B, V, # and Q headers. index-far-scroll checks a Jump to P, then UIA scrolls to 74% → S, 30% → F and 0 → #, then a Jump to M. index-keyboard checks a Tab/Enter/arrows pick.

  | Configuration | Sizes | Result |
  |---|---|---|
  | Display 150% (host default), Dark | compact, medium, wide, maximized, snap-left | All four pages pass; Axe 0 except index-keyboard |
  | High contrast Desert | compact, medium, wide | All pass; system colours and a visible focus rectangle |
  | Text 200% | compact, medium, wide | All pass; labels and the bar grow without clipping |
  | Display 100% | compact, medium, wide | All pass |
  | Light / dark system theme | compact, medium, wide | All pass; the app renders Dark in both (documented deviation) |
  | Keyboard only | all of the above | Jump → label → arrows → Enter lands and names the section; Esc returns to Jump |
  | Narrator / UIA | all of the above | The bar is a Level 2 heading named by the current section; labels are named `ListItem`s with Invoke |

- **Axe:** 0 errors everywhere except the keyboard page, which reports 2 `BoundingRectangleCompletelyObscuresContainer` errors. Both are on the WinUI ToolTip popup host ("Jump to section (Ctrl+Minus)"), open because focus rests on Jump. No app element is involved; this is the framework artifact tracked as open item 8 in `.agents/testing/windows-accessibility.md`. One far-scroll run (High contrast Desert, compact) reported 2 `BoundingRectangleSizeReasonable` findings: after the final Jump to M, a row title sat exactly on the viewport's bottom edge with zero height. That is WinUI viewport-edge clipping (item 3), and the same page scanned 0 everywhere else.
- **Pre-existing, not changed:** after a Jump and several far UIA scrolls, one `SetScrollPercent(0)` can stop in A rather than at the very top. This happens in both the pre-fix and fixed builds; the header correctly says A, and a second scroll reaches #. It is `ItemsStackPanel` virtualization anchoring, outside this control's scope, so the matrix page scrolls to 0 twice before asserting #.
- `winui-code-review` was done by hand; the WinUI analyzer package is not referenced by `Festival.App`, so no analyzer pass ran.
- `winui-design`: `winapp find-ui "grouped list view sticky group headers"` returns the Gallery ListView with Grouped Headers (`gallery-listview-4`), whose platform headers stick without code. This page keeps its own bar for the #288 push and pin, so it has to follow realization. `winapp find-api` describes `ItemsStackPanel.FirstVisibleIndex` as "the first item on the screen", but it only updates once items are realized; hence the post-layout re-read rather than trusting it mid-realization.

## Deliberate deviations from the spec

- One list item per label, not a single adjustable element: `SemanticZoom`'s zoomed-out list is the platform pattern, Narrator reads each label as a list item with its position, and it only exists while open, so it does not lengthen the page's Tab order.
- No drag scrub: Windows has no edge-scrubber idiom; the zoomed-out grid is the Start/Photos/Mail jump-list pattern.

## Tests

- Unit: `SongSectionHeaderTests` (`SectionAt`, `FirstVisibleRow`, `TryFirstVisibleRow` far-scroll cases, `Push`, `PinSlack`, `JumpPinDelta`, `JumpCellWidth`), `MotionPolicyTests` (`HideDuration`), `SongsListTests` and `ViewModelTests` (`HasJumpIndex`).
- UIA: `python tools/windows/songs_journey.py --only songs-jump,songs-sort,songs-search,songs-sort-shop --sizes compact,medium,wide` (`songs-jump` asserts focus on open, Esc from Jump and from the grid, and the heading after a pick); `python tools/windows/a11y_matrix.py --only songs,songs-jump --scan --mode <mode>` for `normal`, `hc-desert`, `hc-night-sky`, `text-200`, `scale-100` and `scale-150`.
- UIA far moves (#248): `python tools/windows/ui_journey.py tools/windows/journeys/songs-section-index.json --large-catalogue` (compact, medium, wide). It scrolls by UIA to 74/30/88/0% and asserts the heading R/G/V/#, then jumps # → P, B, Z, V and M and asserts each heading. The pre-fix build fails at its first far scroll ("#" instead of R).
- Live configurations (#248): `python tools/windows/a11y_matrix.py --live --pages tools/windows/journeys/a11y-section-index.json --scan --sizes compact,medium,wide,maximized,snap-left --mode <mode>`. The pages assert only header names and focus, so they hold on live data.
