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
- App: mark anchors with `controls:QuickLinkAnchor.Id="<web id>"` (x:Bind works in item templates: `controls:QuickLinkAnchor.Id="{x:Bind QuickLinkId}"`), put `controls:QuickLinksMenuButton x:Name="QuickLinksMenu"` in the header and `controls:QuickLinksPane x:Name="Pane"` in an `Auto` column beside the scroller, then one line in the constructor: `new QuickLinksHost(Root, Scroller, model, QuickLinksMenu, Pane)`. The host wraps `QuickLinksBinder` (measures anchors only in `ViewChanged`/`SizeChanged` — nothing per frame while idle; jumps with `ChangeView(disableAnimation: true)` — always instant, a "teleport" (operator batch 7.15)), swaps menu (`IsSuppressed`) and pane at `QuickLinks.UsesPane` of the root's width, and re-reads anchors after the section list changes. Pages whose web links are **mobile-only** pass `pane: null, menuMaxWidth: 640`: the menu shows only on compact pages. Virtualized cards (a `UniformGridLayout` repeater) set `host.Binder.Resolve = id => repeater.GetOrCreateElement(index)` so a jump can realize a card that is off screen. A section laid out *after* a virtualizing repeater sets `host.Binder.LeadIn` to return the repeater's last element (#246, below).
- Landing (#51, iOS #12): a jump puts the anchor's top **32 epx below the scroller's top** (`QuickLinks.LandingOffset`, the web's default offset; both the `ChangeView` path via `QuickLinks.JumpOffset`/`LandingTarget`, including each #46 re-aim, and the repeater `StartBringIntoView` path), and `DefaultActivationOffset` is the same 32 so the landed section is the checked/selected one. Anchors that start with `FSTSectionHeaderStyle` show the title 8 epx lower (the style's top margin).
- Repeater path sign (#251): `BringIntoViewOptions.VerticalOffset` is added to the aligned target position, so the gap above the section is **positive** (`QuickLinks.BringIntoViewOffset`). The #51 port passed −32, which parked Player instrument and Song Detail card targets 32 epx *under* the title bar until the Low-priority landing check re-aimed them (a one-frame overshoot; traced with temporary `PerfLog` lines: first check `top=-32`, after the flip `top=32` with no correction).
- Pinned chrome (#251): Song Detail's compact song header (`PinnedHeader`) overlays its scroller once the full header scrolls away, so a jump to a leaderboard card or band preview landed its title under that header. `QuickLinksBinder.ObscuredTop(offset)` reports the covered height at a scroll offset (`SongDetailLayout.PinnedHeaderInset`: the header's last laid-out height while pinned, `MinFocusTopInset` before it was first shown); `QuickLinks.LandingTarget(…, obscuredTop)` lands sections 32 epx below it, and `Report` shifts frames and the viewport by it so the activation line moves with the landing line.
- Page models expose `QuickLinkSections` (or own a `QuickLinksViewModel`) so section lists are unit-tested in Core; pages whose model is replaced per navigation (Player/Statistics, Rival Detail, Song Detail) keep one view-owned `QuickLinksViewModel` and mirror the model's sections.
- IDs: `fst.quick-links.open`, `fst.quick-links.pane`, `fst.quick-links.list`, `fst.quick-links.item.<id>` (set on the ListViewItem container / menu item).
- **Virtualization and landing (issue #46):** a repeater measures its unrealized cards with *estimated* heights. So a section inside it or below it (profile instruments, `bands`) is first aimed at a guessed position. When the cards around the new viewport realize, the page extent changes: the target moves, or the offset clamps at the end. Before the fix, a medium-width profile jump to Bands landed on Bass, and instrument/end-of-page jumps released the checkmark to a neighbour. The binder now keeps a jump pending until it lands. Rest events report as intermediate; a Low-priority `CheckLanding` runs `UpdateLayout`, re-measures and re-aims (at most `QuickLinks.MaxJumpCorrections`), then settles. The binder also hooks each walked repeater's `ElementPrepared`/`ElementClearing` events to re-collect anchors, and it ignores pooled children (`GetElementIndex < 0`) and recycled ones (anchor ID no longer matches). Verified with `uiwin.py` from a fresh launch for each target (medium and wide profile, Settings, compact Song Detail): every jump settles `Owned` on its target.
- **Multi-column rows (issue #213):** the web picks the *last* section whose top is at or above the activation line, which is fine for its single-column pages. On the Rivals masonry hub (`/compete`), at the top of the page Quick Links named the second card of the first row ("Common"/"Bass Rivals"). Two things caused it. FadeIn's staggered 12-epx composition Translation shows up in `TransformToVisual`, so the last report, taken mid fade-in, skews tops within a row by several epx. On top of that, the last-wins rule picks the later card. `QuickLinks.NaturalActive` now finds the row top (the greatest top at or above the line) and returns the first section in display order whose top is within `QuickLinks.RowTolerance` (FadeIn offset + 4 = 16 epx) of it. Single-column pages are unchanged. `QuickLinksBinder` also re-reports when the scroller content resizes (masonry reflow without a scroll). Regression checks: the `NaturalActiveInMasonryRowsKeepsFirstOfRowAndFollowsLatestTop` unit test and the `compete` scenario in `tools/windows/rivals_journey.py`, which waits for "Quick Links, current section Common Rivals".
- **Menu order (issue #46 cross-check of iOS #6):** the menu and the pane add items in `QuickLinksViewModel.Items` order, which is the page's declared section order. WinUI `MenuFlyout` does not reorder by placement, so the iOS bottom-anchored reversal does not apply.
- **UIA Toggle (issue #202):** a `RadioMenuFlyoutItem`'s automation peer exposes only *Toggle*, not *Invoke*. Narrator's default action and other UIA clients check the item without raising `Click`, so jumps used to do nothing. The menu now also jumps when an item becomes checked, once per opening (`Choose`; a pointer or keyboard pick does both). Journeys drive menu items with `toggle:`. `invoke:` falls back to a mouse click, which can't reach a locked shared session.

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings` (no `diagnostics`: removed in #374), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `privacy-policy`, `reset`; `refresh-profile-name`/`export` omitted (no such rows). At ≥ 1100 epx Settings is list/detail (#371, below), so it shows the header menu, never the pane |
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
| `jumped` | `ql-jumped` (same), `ql-split-jumped` (wide, maximized; was `ql-pane-jumped` before #371) | Down×9, Enter → current section Licenses and focus on `fst.settings.licenses`; in the #371 list/detail split, focus on the `fst.settings.detail-row.licenses` row with the placeholder still showing |
| `active-section` | `ql-active-section` (compact, medium); `ql-pane-active-section` (wide) removed in #371 (Settings no longer shows the pane) | Scrolling (no jump) moves the current section: at the end of Settings it is First Run Guides (spec rule 1: the short Licenses/Privacy/Reset rows never reach the line) |
| pane keyboard | `ql-pane-keyboard` removed in #371 (Settings no longer shows the pane); pane keyboard stays covered by `kb-quick-links-pane` | End focuses Reset, the list scrolls it into view, App Settings stays selected |

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

## Landing validation (issue #251, 2026-10-05)

Journey: `tools/windows/journeys/quick-links-landing.json` (fixture service; `a11y_matrix.py --pages … --scan`). Each page jumps through the real control (`toggle:` a menu item or `invoke:` a pane row) and measures the landing with `assertinset` (the UIA top of the target below the top of the page scroller, ±1 epx), then checks the current-section name or the pane row's `selected=true`.

What the UIA numbers mean: the anchors land at exactly 32 epx (`TransformToVisual`). UIA shows **40** for Settings headings and Player instrument groups because the heading starts after `FSTSectionHeaderStyle`'s 8-epx top margin, and an `AccessibleGroup`'s rectangle starts at its visible content. Leaderboards cards read **32**. On compact Song Detail the landing line is the pinned song header (≈57.7 epx at 100% text) + 32, so the Drums card reads **89.7**. Duos reads **97.7** because its `CardHeader` has no subtitle, so the title is centred in its 44-epx minimum height.

| Configuration | Pages (sizes) | Result |
|---|---|---|
| Normal (300% host) | Settings menu (compact, medium, snap-left, maximized), Leaderboards and Player menus (compact, medium), Song Detail (compact) | Pass. Axe 0, except 2 on maximized Settings (the clipped live-status `TextBlock`, below) |
| Display 150% | Settings pane (wide, maximized), Leaderboards and Player panes (wide) | Pass, Axe 0. Pane jumps to the last sections (Leaderboards Duos, Player Pro Lead) stop at the end of the page; the row is still selected (spec near-end lock), so the inset checks use Solo Drums |
| Display 100% | Settings, Leaderboards, Player panes (wide) | Pass, Axe 0 |
| High contrast Desert | Settings (compact, maximized), Leaderboards, Player, Song Detail menus (compact) | Pass. Axe 0, except 2 on maximized Settings: the live-status `TextBlock` clipped to zero height at the viewport edge ([windows-accessibility item 3](../../testing/windows-accessibility.md)) |
| High contrast Night sky + 150% | Settings, Leaderboards, Player panes (wide) | Pass, Axe 0 |
| Light theme | Settings, Leaderboards, Player menus (medium), Song Detail (compact) | Pass, Axe 0 (dark-only app; unchanged) |
| Dark theme | Settings menu (snap-left) | Pass, Axe 0 |
| Text 200% | Settings, Leaderboards, Player menus (compact, medium), Song Detail (compact, `qll-song-menu-text-200`) | Pass, Axe 0. The pinned header grows with the text (≈81 epx) and the landing line follows it: Drums reads 113.3, Duos 115.3 |
| Keyboard only | `kb-quick-links-menu` (compact, medium), `kb-quick-links-pane` (wide, 150%) | Pass: Down/Enter in the menu and Enter in the pane land the section and move focus into it |

Fixed in #251:

- **Overshoot on the repeater path.** `StartBringIntoView` passed `VerticalOffset = −32`. WinUI adds the offset to the aligned position, so Player instruments and Song Detail cards first parked 32 epx under the title bar, and the landing check moved them back a frame later. It now passes `+QuickLinks.BringIntoViewOffset`, and the first landing is correct.
- **Song Detail under the pinned header.** On compact Song Detail the pinned song header covered the jumped Drums/Duos titles. `ObscuredTop` (see API) lands them below it, and the current-section line moves with the landing line.

Design (`winui-design` skill, Fluent layout and scrolling): no markup, brush or control changes. The jump stays an instant `ChangeView`/`StartBringIntoView` (operator batch 7.15), and the 32-epx offset is the web's default scroll margin.

## Landing accessibility (issue #416, 2026-10-08)

`tools/windows/journeys/a11y-quick-links-landing.json` (`a11y_matrix.py`; guard `tools/windows/tests/test_quick_links_landing_a11y.py`) pins what #51 changed on Settings and Leaderboards, keyboard only. Pages are fixture-only (`"fixture": []`): they focus fixture rows.

- `qla-settings-menu` (compact, medium, snap-left): Enter opens the menu on App Settings; Down walks the page order to Show Instruments, then Accessibility. Each jump announces "… section", lands the level-2 heading 40 epx below the scroller top (`LandingOffset` + the header style's 8 epx), reads it before the section's first control, focuses that control (the Lead toggle, Reduce Motion) and keeps "current section …" on the button one second after the jump settles. Esc returns focus to the ≥ 40×40 epx button.
- `qla-leaderboards-menu` (compact, medium): the same for Drums (card group at 32 epx, its heading before its View All button, focus on its first row).
- `qla-leaderboards-pane` (wide at display 100% or 150%): Enter on the focused ≥ 40-epx Drums row does the same and moves the UIA selection from Lead to Drums.
- `assertstate:…|heading=2` (new driver key) proves the landed title is a heading; the Narrator model's phrase omits heading levels.

| Configuration | Result |
|---|---|
| Menus: compact, medium, snap-left (300% host) | Pass, Axe 0 before the menu opens |
| Menus: text 225%, compact and medium | Pass, Axe 0: headings, focus and current section unchanged; the title still lands fully below the title bar |
| Pane: wide at display 150% and 100% (`--scan`) | Pass, Axe 0 |

No accessibility defect found. A final `--scan` after a menu opened reports only open item 8 (WinUI `PopupHost`).

## Validation (issue #246, 2026-10-05)

#46 asked that Quick Links list sections in on-page order on Settings and on a player profile, from every entry point, and that jumps land and stay marked. Order journeys in `journeys/quick-links.json`:

- `ql-menu-order` / `ql-split-order` (Settings, compact, medium, snap-left and maximized / wide and maximized; `ql-pane-order` until #371) chain `assertbelow:` through every item in the menu and jump to Version.
- `ql-profile-menu-order` / `ql-profile-pane-order` do the same on the Statistics profile, jumping to Drums and then Bands; `ql-profile-route-menu-order` uses the `/player/<id>` route.
- `ql-profile-bands-direct` jumps straight to Bands (run it with `--mode text-200` to stress estimation).

`QuickLinksOrderMarkupTests` checks that the XAML anchor order equals the declared section order on both pages.

| Configuration | Result |
|---|---|
| Compact, medium, snapped left, maximized (300% host) | Pass: menu order matches the page on Settings and profile; jumps land and stay checked; Axe 0 |
| Wide and maximized at display 150% and 100% | Pass: pane order matches; jumps select the landed row; Axe 0 |
| Light, dark system theme | Pass (dark-only app, documented deviation) |
| Desert, Night sky | Pass: order, jumps, Axe 0 |
| Text 200% | **Fixed**: in a compact window, a profile Bands jump sometimes stopped on Pro Lead or near the top (see below). Settings menu/pane and the medium profile passed. A wide profile pane scan reported only the viewport-edge `BoundingRectangleSizeReasonable` artifact on a clipped empty-state text ([open item 3](../../testing/windows-accessibility.md#open-issues)) |
| Keyboard only | Pass: `kb-quick-links-menu` (compact, medium), `kb-quick-links-pane` (wide at 150%) |

**Bands after a virtualizing repeater (#246).** Bands is laid out *below* the instruments `ItemsRepeater`, so its position depends on the repeater's estimated card heights. At 200% text these swing widely: the same profile was estimated at 11,875, 5,067 and 2,812 epx before realizing at 4,651. The #46 re-aim loop then failed in two ways. It either cycled with period 4 (1988 → 1286 → 3387 → 817 …) and never converged, even with 12 corrections, or it settled at the end clamp of an underestimated extent; when the cards realized, the view sat on Pro Lead. `QuickLinksBinder.LeadIn` now lets a page name an element to bring into view first. The profile returns the last instrument card (`GetOrCreateElement(count - 1)`), whose `StartBringIntoView` realizes it at an exact position, and `CheckLanding` aims at Bands from there. Traced runs now land on the first check (offset = scrollable end, extent 4,651).

## Order validation (issue #250, 2026-10-05)

Issue #50 re-checked iOS #11 (nested sections listed bottom-up) on Windows. It found every menu already in page order but committed no test, and #250 re-validated it. Result: **not reproduced, no app change**. Two order guards were added:

- `QuickLinksOrderMarkupTests` (Core) reads each page's `QuickLinkAnchor.Id` markers in XAML document order. Bound anchors inside a repeater template count as `template:<x:DataType>`. The tests require the declared order to match for Settings (Debug and Release), Band Detail, Song Detail, Player Profile, Leaderboards, Rivals and Rival Detail. Song Detail runs through the real view model with and without a player. Score History is listed exactly when `History.IsVisible`, the same binding that shows the card.
- `tools/windows/journeys/quick-links-order.json` (`a11y_matrix.py --scan`) opens each real menu and asserts each item's centre is below the previous item's (`assertbelow`). It checks for the anonymous Song Detail that Score History is absent. At wide sizes it does the same over the pane rows. On Song Detail and Compete it toggles every item in turn (UIA Toggle, locked-console safe) and requires the button to read "current section X".

| Configuration | Result |
|---|---|
| Menu: compact, medium, snap-left (Song Detail and Rival Detail compact only: web mobile-only) | Pass: every page's menu is in page order; Song Detail and Compete jump-walks land on each section |
| Pane: wide and maximized at display 150% (Settings, Compete, Leaderboards, Profile, Band) | Pass: rows in page order |
| Pane: wide and maximized at display 100% | Pass |
| High contrast: Desert (compact menus), Night sky + display 150% (wide panes) | Pass |
| Text 200%, compact menus | Pass. Score History sits below the fold, so the journey `reveal`s `fst.history` (`waitfor` needs it on screen) |
| Light system theme (Song Detail, Compete) | Pass; the app stays dark by design |
| Keyboard | `kb-quick-links-menu` (compact, medium) and `kb-quick-links-pane` (wide, display 150%) pass; Down/Enter in the menu follows the visual order |
| Live service (SFentonX) | Song Detail menu and wide Compete pane match the page order. Live Compete has no Common section, so the first entry is Lead Rivals |
| Axe | 0, except WinUI's `PopupHost` after a menu was opened (open item 8) |

## Settings list/detail (issue #371, 2026-10-08)

When Settings is at least 1100 epx wide, it becomes list/detail ([split-panes](../../patterns/split-panes.md) R6; [settings/windows.md](../../pages/settings/windows.md#wide-listdetail-issue-371-owner-approved)). The Quick Links header menu stays above the list, as on Android ("Quick Links still scroll the list only"). The side pane (≥ 1150) never shows on Settings, because the detail column takes that space. In the split, the section anchors move to the chevron rows (`ApplyQuickLinkAnchors`, `SettingsDetails.QuickLinkId`), and a jump lands the row 32 epx below the top (UIA reads 32, as the row has no header margin). A focusable anchor that is a `Control` takes focus itself (`QuickLinksBinder.Land`), so a keyboard jump focuses the row. The detail pane is unchanged: a jump doesn't open the entry.

Journeys (they need the split, so use display 150% or collapse the nav pane with `invoke:id=PART_PaneToggleButton` on this 300% host):

- `ql-split-jumped` and `ql-split-order` in `quick-links.json`;
- `qll-settings-split` in `quick-links-landing.json` (Accessibility clamps at the end of the list in short windows, so it is checked by name and focus only);
- `qlo-split-settings` in `quick-links-order.json`.

These replace `ql-pane-jumped`, `ql-pane-active-section`, `ql-pane-keyboard`, `ql-pane-order`, `qll-settings-pane` and `qlo-pane-settings`. All passed when driven live with the nav pane collapsed (1280×672 epx).

## Open

The Axe popup-host finding with the menu open (open item 8) is in WinUI, not app markup.
