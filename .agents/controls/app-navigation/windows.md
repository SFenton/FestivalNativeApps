# App navigation — Windows notes

> **What:** WinUI 3 shell navigation, design decisions and validation results. **Read when:** changing the pane, title bar, section history or `fst.nav.*` on Windows. Spec: [spec.md](spec.md). Chrome: [design/windows.md](../../design/windows.md).

## Implementation

- `windows/Festival.App/MainWindow.xaml`: one `NavigationView` (`Nav`, `fst.shell.navigation`) with `PaneDisplayMode="Auto"`, `OpenPaneLength="240"`, its own back and pane-toggle buttons hidden. The WinUI `TitleBar` (`fst.shell.title-bar`) owns Back (`OnBackRequested`) and the pane toggle (`PART_PaneToggleButton`, `OnPaneToggleRequested`), so they sit in the caption row. Below 641 epx the pane is LeftMinimal (an overlay that light-dismisses), from 641 to 1007 epx LeftCompact (icon rail), and Expanded from 1008 epx up. Closing the pane in a wide window is remembered (`expandedPaneCollapsed`), so a compact overlay doesn't leave a wide window on the rail.
- `MainWindow.xaml.cs` `RebuildMenu` builds the items from `ShellState.Sections` (Core) with Segoe Fluent glyphs and `AppSection.AutomationId()` (`fst.nav.songs`, `fst.nav.suggestions`, `fst.nav.statistics`, `fst.nav.rivals`, `fst.nav.leaderboards`, `fst.nav.shop`). Settings is the NavigationView's own footer item (`IsSettingsVisible`, `fst.nav.settings`). Anonymous: Songs, Leaderboards, Item Shop + Settings. With a player: Songs, Suggestions, Statistics, Rivals, Leaderboards, Item Shop + Settings. If the current section disappears (deselect on Statistics), the shell shows Songs.
- `OnNavItemInvoked` calls `Show(section)`: switching restores the section's saved nested route; invoking the current section pops it to its root (spec "re-tapping returns to root").
- `MainWindow.Accessibility.cs`: each item gets `KeyboardAccelerator` Ctrl+1…7 in pane order (Settings Ctrl+comma) and an access key (Alt+S Songs, U Suggestions, T Statistics, R Rivals, L Leaderboards, I Item Shop, E Settings; P the profile button). UIA exposes them as AcceleratorKey "Control+1" / AccessKey "Alt, S". Back is Alt+Left; the content host `FrameHost` is the `main` landmark "Page content".
- Profile: `fst.shell.profile` (anonymous: flyout with `fst.profile.search`; with a player: the Statistics section, issue #290; Ctrl+Shift+P and its context menu open the flyout in both states) and, with a player only, the bell `fst.shell.notifications`. Selecting or deselecting a player rebuilds the pane but keeps the current section.

## Design decisions (winui-design)

- `references/controls.md` / navigation pattern: "2–7 sections → NavigationView". The shell has 4 (anonymous) or 7 (player) sections, so `NavigationView` with `PaneDisplayMode=Auto` gives the system Minimal/Compact/Expanded adaptation; no custom breakpoints.
- `winapp find-ui "navigation"` returns the Gallery NavigationView sample, whose guidance is "Handle SelectionChanged, NOT ItemInvoked". **Deliberate deviation:** the shell handles `ItemInvoked`, because SelectionChanged doesn't fire when the user invokes the already-selected item, and the spec requires that to pop the section to its root. Selection is still set in code (`SelectNavItem`), so UIA `IsSelected` stays right.
- `references/theme-accessibility.md`: "Custom theme dictionaries cover Light, Dark, and HighContrast explicitly — never Default". **Deliberate deviation:** `Themes/Styles.xaml` keeps a `Default` dictionary plus `HighContrast`, because the app is dark-only (`RequestedTheme="Dark"`, issue #195, [design/windows.md](../../design/windows.md)); there's no Light branch to resolve. The nav pane uses no custom brushes, so under a contrast theme it uses system colours. The pane never sets `HighContrastAdjustment=None` (only controls that already pair HighlightText with Highlight do, such as the bell's unread badge).
- Keyboard: the pane is one Tab stop with arrow-key roving (Up/Down move, Enter/Space invoke), and focus entering it lands on the **selected** item. NavigationView only redirects Tab to the selected item when the Tab KeyDown bubbles through the NavigationView itself (`OnRepeaterGettingFocus` checks `m_TabKeyPrecedesFocusChange`, set in `OnKeyDown`). Back, the pane toggle, search and profile live in the separate `TitleBar`, so before #225 Tab from the profile button (and Enter on the toggle in a compact window) landed on Songs whatever was selected. `MainWindow.Accessibility.cs` `OnNavGettingFocus` restores the platform behaviour: a keyboard Next/Previous move from outside the pane, or the minimal pane's programmatic focus on opening (no direction, keyboard or no device), is redirected to the selected item. Pointer focus and moves within the pane are untouched. The decision is `PaneFocus.ShouldRedirect` in Core (unit-tested); Settings (footer) and the menu items are separate groups, so Shift+Tab into the footer stays on Settings.
- The open minimal pane is a light-dismiss overlay, so Tab cycles within it (menu ↔ Settings) and Esc closes it, returning focus to the toggle. That matches WinUI's overlay behaviour; it isn't changed.
- `band` state: band search is a blocked production read ([service-safety.md](../../platforms/service-safety.md)), so Windows can't select a band identity. On Windows `band` means a band page pushed inside a section (Leaderboards › Band Rankings › band) with title-bar Back and pop-to-root. The pane never shows band-only sections.

## States and reachability

Runner: `python tools/windows/journeys/navigation.py [NAMES] [--shots DIR]` (fixture service with UIA patterns only, so it passes on a locked console). Unit tests: `tools/windows/tests/test_navigation_journeys.py`.

| State | Reached by | Journey (asserts) |
|---|---|---|
| `songs` | Launch anonymous | `songs`: Songs selected; anonymous pane order; accelerators/access keys; profile access key; `main` landmark; no player-only items or bell |
| `leaderboards` | `select:id=fst.nav.leaderboards` | `leaderboards`: View All pushes with Back; Ctrl+1 then Ctrl+2 restores the nested route; re-selecting pops to root |
| `settings` | Ctrl+comma, or the footer item | `settings`: Settings selected, no Back, both entry points |
| `player` | Selected player at launch | `player`: seven-item pane order and accelerators, bell visible; Statistics, Suggestions (Ctrl+2) and Rivals (Ctrl+4) selected in turn |
| `band` | Leaderboards › Band Rankings › band | `band`: band page with Back and no player-only items; Alt+Left returns; re-selecting Leaderboards pops to root, Back gone |
| `reselect` | Statistics › Deselect › confirm, then profile flyout › search › Select | `reselect`: pane drops to the anonymous order and lands on Songs; selecting again restores the seven items and keeps Songs selected; Ctrl+1 then the profile button opens Statistics with no flyout (issue #290) |
| Compact pane | `compact` preset, `PART_PaneToggleButton` | `compact`: pane closed until toggled; on Leaderboards, Enter on the toggle opens it with focus on Leaderboards and Esc returns focus to the toggle; an item navigates and the overlay dismisses; resizing to wide keeps the selection |
| Keyboard | Posted keys at `medium` | `keyboard`: Ctrl+5/6/comma/1; Alt+Left; Tab toggle → search → bell → profile → the selected item (Leaderboards); Down + Enter navigates to Item Shop |

Accessibility matrix pages: `tools/windows/journeys/a11y-navigation.json` (`nav-anonymous`, `nav-player`, `nav-band`, `nav-settings`, `nav-pane-open` at compact).

## Validation (issue #225, 2026-10-04)

Matrix: `a11y_matrix.py --pages tools/windows/journeys/a11y-navigation.json --scan --tabs 30` (fixture service), then `navigation.py` (8/8 journeys pass after the fix). Live: the Debug build on the public HTTPS origin with SFentonX selected (public profile reads only), anonymous, and a band page reached through Leaderboards › Band Rankings.

| Configuration | Result |
|---|---|
| Compact (LeftMinimal, toggle in the title bar) | Pass. 0 Axe errors on nav-anonymous/player/band/settings; Tab stops anonymous 8, player 17, band 12, none outside the window or repeated. Pane-open: Tab cycles Songs ↔ Settings inside the light-dismiss overlay, Esc returns focus to the toggle. **Fixed:** Enter on the toggle focused Songs whatever was selected. |
| Medium (LeftCompact rail) | Pass. 0 Axe errors; icons with tooltips and accelerators; selection pill visible. **Fixed:** Tab from profile landed on Songs instead of the selected section. |
| Wide (Expanded, 240 epx pane) | Pass. 0 Axe errors; player 18–20 Tab stops, band 14–15. Same Tab fix as medium. |
| Snapped left / right | Pass. Snap halves are compact-width here (work area 1280×672 epx at 300%), so the pane is LeftMinimal; 0 Axe errors. |
| Maximized | Pass. Expanded pane, 0 Axe errors. |
| Light theme (system) | Pass. The app stays dark (issue #195); 0 Axe errors on player at compact and wide. |
| Dark theme | Pass. 0 Axe errors on player at compact and wide. |
| High contrast (Desert, Night sky) | Pass. System Highlight on the selected item, system focus rectangle, readable glyphs; 0 Axe errors on player and band at compact and wide. |
| Text 200% | Pass. Labels don't clip in the 240 epx pane; tooltips at the rail; 0 Axe errors at compact, medium and wide, including pane-open. |
| Display 100% / 150% | Pass. 0 Axe errors on player and pane-open; breakpoints follow effective pixels. |
| Keyboard only | Pass after the fix. Ctrl+1…7 / Ctrl+comma, Alt access keys, Alt+Left, title bar → pane landing on the selected section, arrows + Enter, Esc closes the overlay. |
| Pane-open overlay (all modes) | 2 Axe `BoundingRectangleCompletelyObscuresContainer` findings on WinUI's `InputSiteWindowClass` inside the `PopupHost` light-dismiss bridge, in the normal, light, dark and HC runs (none at text 200% or display 100%/150%). No app element is involved: framework issue, the same as [windows-accessibility.md](../../testing/windows-accessibility.md) open issue 8. |

The console was locked during this pass, so Narrator itself wasn't run and pointer input couldn't be tested. Reading order was checked from the UIA tree: title bar (pane toggle, Back when present, search, bell, profile) → pane items in order with `ListItem` role, selected state, accelerator and access key → Settings footer → `main` "Page content".

## Validation (issue #253, 2026-10-05): bell and profile as separate title-bar buttons

Check of #53/#14: the bell (`fst.shell.notifications`, player only) and the avatar (`fst.shell.profile`) are two sibling `Button`s in `TitleBar.RightHeader` (after search), not one container. `HitTargetMarkupTests.TitleBar_BellAndProfileAreSeparateNamedButtons` guards the markup. Pages: `tools/windows/journeys/a11y-titlebar-buttons.json`, run with `a11y_matrix.py --pages tools/windows/journeys/a11y-titlebar-buttons.json --scan` (fixture service with `notifications_fixture.py`, rich feed, 5 unread):

- `tb-player` asserts the names "Notifications, 5 unread" and "Profile: Fixture Player 1" and that both buttons sit on one row. Tab moves bell → avatar and Shift+Tab moves back. Enter on the bell opens `fst.notifications.sheet`, and Esc returns focus to the bell. Enter on the avatar opens Statistics without the picker (#290). Ctrl+Shift+P opens the picker with Deselect, and Esc closes it. After the flyout has marked the rows seen, the bell reads "Notifications".
- `tb-anonymous` asserts there's no bell, the avatar reads "Select a player profile", and Enter opens the picker with focus back on the avatar after Esc.

| Configuration | Result |
|---|---|
| Compact 500, medium 900, wide 1440 epx, maximized, snapped left | Pass, 0 Axe errors (10 runs). At compact the TitleBar drops its title and search collapses to a button, while search, bell and avatar stay visible and reachable. |
| Light / dark system theme (C/M/W) | Pass, 0 Axe errors. The app stays dark (issue #195). |
| High contrast Aquatic, Desert (C/M/W) | Pass, 0 Axe errors. System focus rectangle and ButtonText glyphs. **Fixed:** the badge count drew the automatic text backplate (a dark box under Aquatic, a light one under Desert) clipped inside the Highlight circle. InfoBadge already pairs HighlightText with Highlight there, so the badge and its template parts opt out (`NotificationsBell.OnBadgeLayout` → `DialogChrome.WithoutBackplate`), guarded by `HitTargetMarkupTests.NotificationsBadge_HasNoContrastBackplate`. |
| Text 200% (C/M/W) | Pass, 0 Axe errors. The badge stays inside its 16 epx circle (fixed earlier, #229), and both buttons keep their 40 epx targets in the compact title bar. |
| Display 100% / 150% (C/M/W) | Pass, 0 Axe errors; the same epx layout. |
| Keyboard only | Pass. Tab order: pane toggle → search → bell → avatar → the selected pane item. Enter/Esc work on both flyouts, focus returns to the invoking button, and Alt+P / Ctrl+Shift+P reach the profile. |
| Live service (SFentonX and anonymous) | The same two buttons and names on the public HTTPS origin (public reads only). |

UIA: each is a `Button` with its own name and AutomationId. The badge and glyph are `Raw`, so Narrator reads "Notifications, 5 unread, button", then "Profile: Fixture Player 1, button". winui-design: `winapp find-ui` returns the TitleBar sample (`gallery-titlebar-3`, TitleBar above NavigationView, buttons in RightHeader), plus InfoBadge and PersonPicture. `find-api` against the app project confirms `InfoBadge.Value`/`IsTextScaleFactorEnabled` and `PersonPicture.DisplayName`. No deviation beyond the dark-only theme.
