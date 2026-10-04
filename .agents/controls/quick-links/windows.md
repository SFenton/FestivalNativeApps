# Quick Links — Windows notes

> **What:** the Windows Quick Links idiom (menu vs persistent pane), the reusable API and adoption steps. **Read when:** adding section navigation to any Windows page. Behavior: [spec.md](spec.md).

## Design decision

| Page-area width | Presentation | Why |
|---|---|---|
| < 1150 epx | "Quick Links" `DropDownButton` in the page header (`fst.quick-links.open`, bulleted-list glyph) opening a `MenuFlyout` of `RadioMenuFlyoutItem`s; the current section is checked | Fluent: a drop-down menu picks one of a small set of destinations without leaving the page; radio check = `aria-current` |
| ≥ 1150 epx (≈1440-epx window with the 240-epx nav pane) | Persistent right pane (`Controls/QuickLinksPane.xaml`, 240 epx card, `LandmarkType=Navigation`); the current section is the selected `ListViewItem`. Rows are at least `FSTMinTargetSize` (40 epx); the list fills the card's remaining height and scrolls in short windows; arrow keys move focus only (`SingleSelectionFollowsFocus="False"`), Enter/Space/click jump; titles wrap at large text (issue #230) | Web ≥1440 px rail; Learn-style "In this article" pane; selecting scrolls without closing anything |

The breakpoint is page-area width (`QuickLinks.UsesPane`), not window width, so it adapts to the nav pane state and snapped windows.

## API

- Core: `Domain/QuickLinks.cs` (port of Apple `QuickLinks`/`QuickLinkTracker`: ≥2 sections, natural active line, jump ownership, near-end lock) and `ViewModels/QuickLinksViewModel.cs` (`SetSections`, `Jump`, `ReportLayout`, `EntryName` "Quick Links, current section …").
- App: mark anchors with `controls:QuickLinkAnchor.Id="<web id>"` (x:Bind works in item templates: `controls:QuickLinkAnchor.Id="{x:Bind QuickLinkId}"`), put `controls:QuickLinksMenuButton x:Name="QuickLinksMenu"` in the header and `controls:QuickLinksPane x:Name="Pane"` in an `Auto` column beside the scroller, then one line in the constructor: `new QuickLinksHost(Root, Scroller, model, QuickLinksMenu, Pane)`. The host wraps `QuickLinksBinder` (measures anchors only in `ViewChanged`/`SizeChanged` — nothing per frame while idle; jumps with `ChangeView(disableAnimation: true)` — always instant, a "teleport" (operator batch 7.15)), swaps menu (`IsSuppressed`) and pane at `QuickLinks.UsesPane` of the root's width, and re-reads anchors after the section list changes. Pages whose web links are **mobile-only** pass `pane: null, menuMaxWidth: 640`: the menu shows only on compact pages. Virtualized cards (a `UniformGridLayout` repeater) set `host.Binder.Resolve = id => repeater.GetOrCreateElement(index)` so a jump can realize a card that is off screen.
- Landing (#51, iOS #12): a jump puts the anchor's top **32 epx below the scroller's top** (`QuickLinks.LandingOffset`, the web's default offset; both the `ChangeView` path via `QuickLinks.JumpOffset`/`LandingTarget`, including each #46 re-aim, and the repeater `StartBringIntoView` path), and `DefaultActivationOffset` is the same 32 so the landed section is the checked/selected one. Anchors that start with `FSTSectionHeaderStyle` show the title 8 epx lower (the style's top margin).
- Page models expose `QuickLinkSections` (or own a `QuickLinksViewModel`) so section lists are unit-tested in Core; pages whose model is replaced per navigation (Player/Statistics, Rival Detail, Song Detail) keep one view-owned `QuickLinksViewModel` and mirror the model's sections.
- IDs: `fst.quick-links.open`, `fst.quick-links.pane`, `fst.quick-links.list`, `fst.quick-links.item.<id>` (set on the ListViewItem container / menu item).
- **Virtualization and landing (issue #46):** a repeater measures its unrealized cards with *estimated* heights. So a section inside it or below it (profile instruments, `bands`) is first aimed at a guessed position. When the cards around the new viewport realize, the page extent changes: the target moves, or the offset clamps at the end. Before the fix, a medium-width profile jump to Bands landed on Bass, and instrument/end-of-page jumps released the checkmark to a neighbour. The binder now keeps a jump pending until it lands. Rest events report as intermediate; a Low-priority `CheckLanding` runs `UpdateLayout`, re-measures and re-aims (at most `QuickLinks.MaxJumpCorrections`), then settles. The binder also hooks each walked repeater's `ElementPrepared`/`ElementClearing` events to re-collect anchors, and it ignores pooled children (`GetElementIndex < 0`) and recycled ones (anchor ID no longer matches). Verified with `uiwin.py` from a fresh launch for each target (medium and wide profile, Settings, compact Song Detail): every jump settles `Owned` on its target.
- **Multi-column rows (issue #213):** the web picks the *last* section whose top is at or above the activation line, which is fine for its single-column pages. On the Rivals masonry hub (`/compete`), at the top of the page Quick Links named the second card of the first row ("Common"/"Bass Rivals"). Two things caused it. FadeIn's staggered 12-epx composition Translation shows up in `TransformToVisual`, so the last report, taken mid fade-in, skews tops within a row by several epx. On top of that, the last-wins rule picks the later card. `QuickLinks.NaturalActive` now finds the row top (the greatest top at or above the line) and returns the first section in display order whose top is within `QuickLinks.RowTolerance` (FadeIn offset + 4 = 16 epx) of it. Single-column pages are unchanged. `QuickLinksBinder` also re-reports when the scroller content resizes (masonry reflow without a scroll). Regression checks: the `NaturalActiveInMasonryRowsKeepsFirstOfRowAndFollowsLatestTop` unit test and the `compete` scenario in `tools/windows/rivals_journey.py`, which waits for "Quick Links, current section Common Rivals".
- **Menu order (issue #46 cross-check of iOS #6):** the menu and the pane add items in `QuickLinksViewModel.Items` order, which is the page's declared section order. WinUI `MenuFlyout` does not reorder by placement, so the iOS bottom-anchored reversal does not apply.

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings`, `diagnostics` (Debug only), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `privacy-policy`, `reset`; `refresh-profile-name`/`export` omitted (no such rows) |
| Leaderboards | Done ("Leaderboards Quick Links"): `instrument:<key>` per card, `band:<type>` per band card (no rank-history graph or promoted band on Windows yet). Menu beside Rank By |
| Rivals (both tabs; also `/compete`) | Done: `common`, `combo`, `<instrumentKey>` per visible section (empty sections drop out, so ≥2 still applies). Replaced the old "Jump To" menu (`fst.rivals.jump*`) |
| Player / Statistics | Done: `global` "Global Statistics" (Overview), `instrument:<key>` per chart, `bands`. `top-songs` omitted (no Windows section yet). Menu beside Select/Deselect |
| Band | Done: `members`, `summary`, `statistics`, `rank-history`, `songs`. Replaced the bespoke pill bar/rail (`fst.band.quick-link*`) |
| Rival Detail | Done, compact only (web: mobile only): `rival-category:<key>` per non-empty category |
| Song Detail | Done, compact only (web: mobile only): `intensity`, `score-history` (while the history card is visible), `instrument-<key>` per leaderboard card (virtualized cards realized on jump), `band-<type>` per band preview |
| Songs | Covered by the grouped list's `SemanticZoom` + **Jump** button (`fst.songs.section-index-button`) for every sort with sections: the Windows idiom for a virtualized list (Start, Mail, Photos). No separate menu |
| Rivalry | Not ported: the web's mobile Rivalry links are unreachable (spec "Known web gaps") |
| Compete | No Windows page (`/compete` opens Rivals) |

## Validation (issue #230, 2026-10-04)

State pages: `tools/windows/journeys/quick-links.json` (Settings on the fixture service; `a11y_matrix.py --scan`), keyboard journeys `kb-quick-links-menu`/`kb-quick-links-pane` in `journeys/a11y-keyboard.json`. This host runs at 300% display scale, so pane pages use `--mode scale-150` (or `scale-100`) and contrast/text-size pane runs combine modes (`hc-desert+scale-150`). Axe 0 errors everywhere except with the menu open (2, the WinUI popup host, [open item 8](../../testing/windows-accessibility.md#open-issues)).

| State | Page (sizes) | Asserts |
|---|---|---|
| `hidden-single-section` | `ql-hidden-single-section` (all) | Licenses page has neither `fst.quick-links.open` nor the pane |
| `menu-closed` | `ql-menu-closed` (compact, medium, snap-left, maximized) | Button "Quick Links, current section App Settings", collapsed |
| `menu-open` | `ql-menu-open` (same) | Menu "Quick Links", first item focused, current item toggled and named "…, current section"; Esc returns focus to the button |
| `jumped` | `ql-jumped` (same), `ql-pane-jumped` (wide, maximized) | Down×9, Enter → current section Licenses and focus on `fst.settings.licenses`; pane Enter on Licenses/Version moves focus into the section |
| `active-section` | `ql-active-section` (compact, medium), `ql-pane-active-section` (wide) | Scrolling (no jump) moves the current section: at the end of Settings it is First Run Guides (spec rule 1: the short Licenses/Privacy/Reset rows never reach the line); pane row `selected=true` |
| pane keyboard | `ql-pane-keyboard` (1440×560) | End focuses Reset, the list scrolls it into view, App Settings stays selected |

| Configuration | Result |
|---|---|
| Compact, medium, snapped left (normal 300% host) | Pass: menu presentation |
| Wide at display 150% and 100%, maximized at 150% | Pass: pane presentation |
| Short wide window (1440×560 at 150%) | **Fixed**: the pane's `StackPanel` gave the `ListView` unlimited height, so Privacy Policy and Reset were clipped and a focused Reset was off screen. Now a `Grid` (`Auto`/`*`) so the list scrolls |
| Light, dark system theme | Pass, unchanged (dark-only app, documented deviation) |
| Desert, Night sky | Pass: menu uses system flyout brushes; pane selection uses Highlight, card outlined |
| Text 200% | Menu: pass (items and button grow). Pane: **fixed**, long titles were cut mid-word ("Show Instrumen") because the row's horizontal `StackPanel` gave the title unlimited width; a `Grid` row now wraps them |
| Keyboard only | **Fixed**: arrow/End keys in the pane moved the selection (the "current section" marker) without jumping. Now `SingleSelectionFollowsFocus="False"`. Menu: Down/Enter, Esc closes |
| Touch target | **Fixed**: pane rows were 36 epx; now `FSTMinTargetSize` (guard: `HitTargetMarkupTests.QuickLinksPane_RowsUseMinTarget`) |

UI Automation (Narrator reads these): button `fst.quick-links.open` is a `Button` (WinUI `DropDownButton`) with ExpandCollapse, name "Quick Links, current section X"; the menu is `Menu` "Quick Links" with `MenuItem`s exposing Toggle (On = current, name suffix ", current section"); the pane is a `Navigation` landmark with a level-2 "Quick Links" heading and a `List` of `ListItem`s with Invoke and SelectionItem (selected = current). Focus order: header button → page content; the pane follows the page content in tab order.

Deliberate deviations: the menu button sits in the scrolling page header (web parity) and scrolls away after a jump; a jump moves keyboard focus to the first focusable element of the target section, so keyboard and Narrator users land where they asked and Shift+Tab/Home returns. Menu items use `RadioMenuFlyoutItem` (one current destination) rather than a plain `MenuFlyoutItem` with a trailing glyph.

## Open

The Axe popup-host finding with the menu open (open item 8) is in WinUI, not app markup.
