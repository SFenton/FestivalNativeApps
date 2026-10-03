# Quick Links — Windows notes

> **What:** the Windows Quick Links idiom (menu vs persistent pane), the reusable API and adoption steps. **Read when:** adding section navigation to any Windows page. Behavior: [spec.md](spec.md).

## Design decision

| Page-area width | Presentation | Why |
|---|---|---|
| < 1150 epx | "Quick Links" `DropDownButton` in the page header (`fst.quick-links.open`, bulleted-list glyph) opening a `MenuFlyout` of `RadioMenuFlyoutItem`s; the current section is checked | Fluent: a drop-down menu picks one of a small set of destinations without leaving the page; radio check = `aria-current` |
| ≥ 1150 epx (≈1440-epx window with the 240-epx nav pane) | Persistent right pane (`Controls/QuickLinksPane.xaml`, 240 epx card, `LandmarkType=Navigation`); the current section is the selected `ListViewItem` | Web ≥1440 px rail; Learn-style "In this article" pane; selecting scrolls without closing anything |

The breakpoint is page-area width (`QuickLinks.UsesPane`), not window width, so it adapts to the nav pane state and snapped windows.

## API

- Core: `Domain/QuickLinks.cs` (port of Apple `QuickLinks`/`QuickLinkTracker`: ≥2 sections, natural active line, jump ownership, near-end lock) and `ViewModels/QuickLinksViewModel.cs` (`SetSections`, `Jump`, `ReportLayout`, `EntryName` "Quick Links, current section …").
- App: mark anchors with `controls:QuickLinkAnchor.Id="<web id>"` (x:Bind works in item templates: `controls:QuickLinkAnchor.Id="{x:Bind QuickLinkId}"`), put `controls:QuickLinksMenuButton x:Name="QuickLinksMenu"` in the header and `controls:QuickLinksPane x:Name="Pane"` in an `Auto` column beside the scroller, then one line in the constructor: `new QuickLinksHost(Root, Scroller, model, QuickLinksMenu, Pane)`. The host wraps `QuickLinksBinder` (measures anchors only in `ViewChanged`/`SizeChanged` — nothing per frame while idle; jumps with `ChangeView(disableAnimation: true)` — always instant, a "teleport" (operator batch 7.15)), swaps menu (`IsSuppressed`) and pane at `QuickLinks.UsesPane` of the root's width, and re-reads anchors after the section list changes. Pages whose web links are **mobile-only** pass `pane: null, menuMaxWidth: 640`: the menu shows only on compact pages. Virtualized cards (a `UniformGridLayout` repeater) set `host.Binder.Resolve = id => repeater.GetOrCreateElement(index)` so a jump can realize a card that is off screen.
- Landing (#51, iOS #12): a jump puts the anchor's top **32 epx below the scroller's top** (`QuickLinks.LandingOffset`, the web's default offset; both the `ChangeView` path via `QuickLinks.JumpOffset`/`LandingTarget`, including each #46 re-aim, and the repeater `StartBringIntoView` path), and `DefaultActivationOffset` is the same 32 so the landed section is the checked/selected one. Anchors that start with `FSTSectionHeaderStyle` show the title 8 epx lower (the style's top margin).
- Page models expose `QuickLinkSections` (or own a `QuickLinksViewModel`) so section lists are unit-tested in Core; pages whose model is replaced per navigation (Player/Statistics, Rival Detail, Song Detail) keep one view-owned `QuickLinksViewModel` and mirror the model's sections.
- IDs: `fst.quick-links.open`, `fst.quick-links.pane`, `fst.quick-links.list`, `fst.quick-links.item.<id>` (set on the ListViewItem container / menu item).
- **Virtualization and landing (issue #46):** a repeater measures its unrealized cards with *estimated* heights. So a section inside it or below it (profile instruments, `bands`) is first aimed at a guessed position. When the cards around the new viewport realize, the page extent changes: the target moves, or the offset clamps at the end. Before the fix, a medium-width profile jump to Bands landed on Bass, and instrument/end-of-page jumps released the checkmark to a neighbour. The binder now keeps a jump pending until it lands. Rest events report as intermediate; a Low-priority `CheckLanding` runs `UpdateLayout`, re-measures and re-aims (at most `QuickLinks.MaxJumpCorrections`), then settles. The binder also hooks each walked repeater's `ElementPrepared`/`ElementClearing` events to re-collect anchors, and it ignores pooled children (`GetElementIndex < 0`) and recycled ones (anchor ID no longer matches). Verified with `uiwin.py` from a fresh launch for each target (medium and wide profile, Settings, compact Song Detail): every jump settles `Owned` on its target.
- **Menu order (issue #46 cross-check of iOS #6):** the menu and the pane add items in `QuickLinksViewModel.Items` order, which is the page's declared section order. WinUI `MenuFlyout` does not reorder by placement, so the iOS bottom-anchored reversal does not apply.
- **UIA Toggle (issue #202):** a `RadioMenuFlyoutItem`'s automation peer exposes only *Toggle*, not *Invoke*. Narrator's default action and other UIA clients check the item without raising `Click`, so jumps used to do nothing. The menu now also jumps when an item becomes checked, once per opening (`Choose`; a pointer or keyboard pick does both). Journeys drive menu items with `toggle:`. `invoke:` falls back to a mouse click, which can't reach a locked shared session.

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings`, `diagnostics` (Debug only), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `reset`; `refresh-profile-name`/`export` omitted (no such rows) |
| Leaderboards | Done ("Leaderboards Quick Links"): `instrument:<key>` per card, `band:<type>` per band card (no rank-history graph or promoted band on Windows yet). Menu beside Rank By |
| Rivals (both tabs; also `/compete`) | Done: `common`, `combo`, `<instrumentKey>` per visible section (empty sections drop out, so ≥2 still applies). Replaced the old "Jump To" menu (`fst.rivals.jump*`) |
| Player / Statistics | Done: `global` "Global Statistics" (Overview), `instrument:<key>` per chart, `bands`. `top-songs` omitted (no Windows section yet). Menu beside Select/Deselect |
| Band | Done: `members`, `summary`, `statistics`, `rank-history`, `songs`. Replaced the bespoke pill bar/rail (`fst.band.quick-link*`) |
| Rival Detail | Done, compact only (web: mobile only): `rival-category:<key>` per non-empty category |
| Song Detail | Done, compact only (web: mobile only): `intensity`, `instrument-<key>` per leaderboard card (virtualized cards realized on jump). `score-history`/`band-<type>` omitted (no such sections; band boards are links) |
| Songs | Covered by the grouped list's `SemanticZoom` + **Jump** button (`fst.songs.section-index-button`) for every sort with sections: the Windows idiom for a virtualized list (Start, Mail, Photos). No separate menu |
| Rivalry | Not ported: the web's mobile Rivalry links are unreachable (spec "Known web gaps") |
| Compete | No Windows page (`/compete` opens Rivals) |

## Open

Narrator landmark/heading navigation replaces the iPhone rotor; not yet audited with Narrator.
