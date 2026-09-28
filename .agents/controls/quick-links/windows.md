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
- App: mark anchors with `controls:QuickLinkAnchor.Id="<web id>"`; create `new QuickLinksBinder(scrollViewer, model, reduceMotion)` (measures anchors only in `ViewChanged`/`SizeChanged` — nothing per frame while idle; jumps with `ChangeView`, instant under reduced motion); put `controls:QuickLinksMenuButton` (set `Model`) in the header and `controls:QuickLinksPane` beside the scroller, toggled from `SizeChanged` with `QuickLinks.UsesPane`. See `SettingsPage` for the complete pattern.
- IDs: `fst.quick-links.open`, `fst.quick-links.pane`, `fst.quick-links.list`, `fst.quick-links.item.<id>` (set on the ListViewItem container / menu item).

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings`, `diagnostics` (Debug only), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `reset`; `refresh-profile-name`/`export` omitted (no such rows) |
| Songs, Song Detail, Player/Statistics, Band, Compete, Rivals, Rivalry, Rival Detail, Leaderboards | Owning lanes: follow the spec table ids/labels. Songs should keep `SemanticZoom` for alphabetical/year jumps and use Quick Links only for other sorts (as iPhone) |

## Open

Narrator landmark/heading navigation replaces the iPhone rotor; not yet audited with Narrator.
