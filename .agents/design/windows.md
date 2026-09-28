# Windows design (WinUI 3)

> **What:** WinUI 3 chrome, Fluent content and motion decisions for the Windows app. **Read when:** laying out Windows screens or adding chrome, cards, headers or motion. Architecture and perf: [platforms/windows.md](../platforms/windows.md).

## Chrome (system-owned)

| Element | Decision |
|---|---|
| Window | `MicaBackdrop` (Base); falls back to solid automatically when transparency is off or the window is inactive |
| Title bar | WinUI `TitleBar` control, `ExtendsContentIntoTitleBar`, tall height; owns Back and pane toggle (NavigationView's own are hidden) |
| Profile | `PersonPicture` button at the **top-right** of the title bar (`TitleBar.RightHeader`, `fst.shell.profile`); flyout with Find Player search, results and Deselect |
| Navigation | `NavigationView` pane: Songs · Suggestions* · Leaderboards · Rivals* · Statistics* (*player selected) · Item Shop (hidden by Hide Item Shop), Settings as the footer item. Wide split set: Leaderboards and Rivals are separate items. `PaneDisplayMode="Auto"` with `CompactModeThresholdWidth="0"`: expanded pane from 1008 epx, icon rail below. Never LeftMinimal: in that mode the extended `TitleBar` rendered blank (back, pane toggle and avatar vanished) |
| Stacks | One `Frame` per section; switching sections keeps each stack; re-invoking the current section pops to root. Alt+Left, the Back key and mouse XButton1 go back |

## Content (branded, Fluent tokens)

- Brand colours come from the generated `contracts/generated/windows/BrandTokens.xaml` (linked, never copied). Content-only brushes (`FSTCardSurfaceBrush`, header, meter) live in `windows/Festival.App/Themes/Styles.xaml` with a `HighContrast` theme dictionary mapping to system colours.
- **Cards** (`FSTCardStyle`): 8 px radius, 1 px stroke, 16 px padding, **solid** `#C7121826` surface. No in-app Acrylic: a blur over animated art is recomputed every frame. When Windows transparency effects are off, the shell makes the card surface opaque at runtime.
- **Section headers** (`FSTSectionHeaderStyle`): white Title Case `SubtitleTextBlockStyle`, heading level 2 for UIA.
- **Songs rows**: ≥ 64 px card rows, 44 px art, title/`artist · year · duration`, 2 px gold (New) / red (Leaving Tomorrow) Shop border; trailing chart meter, status chips or metadata pills that wrap under the title in narrow lists ([songs/windows.md](../pages/songs/windows.md)). Rows have no chevron (card is the target, as on iPhone).
- **Jump index**: `SemanticZoom` (Ctrl+minus / pinch / header tap / **Jump** button) over group headers is the Windows equivalent of the iPhone section scrubber.
- **Wrapping rows of small items** (chips, pills, dialog selectors): `Controls/FlowPanel` (WinUI has no WrapPanel).
- **Difficulty meter**: branded 62×20 geometry from `DifficultyScale` ([spec](../controls/difficulty-meter/spec.md)); one `Image`-typed UIA element.
- Instrument icons: the Apple asset catalogue PNGs (144 px), decoded once at 72 px and shared.

## Motion

- `Controls/MarqueeText`: static ellipsis by default; while its row is hovered or keyboard-focused an overflowing line scrolls a two-copy track (8 s cycle, dwell at the start, 28 epx gap) via a compositor `Translation.X` animation, stopped on exit. Off under system Animation effects off or in-app Reduce Motion. UIA always reads the full text.

Artwork motion follows [artwork-background](../controls/artwork-background/windows.md); system "Animation effects" off or in-app Reduce Motion gives a still cover. Sort/Filter use light-dismiss `Flyout`s: dismissing discards the draft (Fluent pattern) instead of the web's confirm-discard dialog.

## Accessibility

AutomationIds follow the `product.json` families (`fst.nav.*`, `fst.songs.*`, `fst.profile.*`, `fst.service-status.*`, `fst.settings.*`). Decorative art is `AccessibilityView.Raw`. Rows set their UIA name to title + subtitle. Not yet audited with Narrator, text scaling or high contrast.
