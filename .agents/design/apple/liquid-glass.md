# Liquid Glass on Apple platforms (iOS/iPadOS/macOS 26+)

> **What:** Lane A's decision record for which surfaces are Liquid Glass and the shared glass components. **Read when:** adding any container, toolbar item, sheet or floating control on an Apple platform.

Decision record for **which surfaces are Liquid Glass**, owned by Lane A (Shell), 2026-09-27. Every Apple lane follows this table; propose changes to the orchestrator rather than diverging per page.

## Principle

Apple's HIG for iOS 26 puts Liquid Glass on the **navigation/control layer that floats above content** (tab bars, toolbars, sheets, menus, floating controls) and keeps **content** legible and non-refractive. Festival is unusual: every page's content already floats over the shared, animated album-art background (`FestivalBackgroundHost`), and the web renders its containers as frosted glass (`FrostedCard`, `fx.navFrosted`). The operator asked for song rows and glass containers to be Liquid Glass. The resolution:

1. **System chrome is always system glass.** Never hand-build a tab bar, nav bar, search field, sheet or menu to get a glass look; use SwiftUI's and restyle nothing but tint/foreground.
2. **Content containers that the web draws as frosted cards become tinted, non-interactive glass cards** (`festivalGlass(.card)`), because on this app they *are* a layer over a moving background, not the base layer.
3. **Never glass-on-glass.** Anything inside a glass card (chips, pills, badges, meters, nested cards) uses flat fills. Glass inside a glass sheet is also forbidden.
4. **Status and data must stay ≥ 4.5:1.** Warnings, errors, scores and rank numbers never depend on what is refracted behind them.
5. **Accessibility overrides win.** System Reduce Transparency, the in-app *Reduce Transparency* and *Increase Contrast* toggles all replace glass with opaque `BrandTokens.cardBackground` + `borderSubtle`. `festivalGlass`, `FestivalGlassSection`, `festivalSheet` and the drawer already do this — do not bypass them with raw `.glassEffect`.

## Decision table

| Surface | Role | Implementation | Rationale | Pre-26 fallback (iOS 17–25) |
|---|---|---|---|---|
| Tab bar (iPhone) | System nav | `TabView { Tab(…) }` in `FestivalRootView` | System Liquid Glass tab bar, minimises and adapts automatically | Classic translucent tab bar (`.tabItem` on iOS 17) |
| Navigation bar + toolbar items | System nav | `.toolbar { ToolbarItem(…) }`; shared items via `festivalRootChrome(session:)` | System glass capsules; `ToolbarSpacer(.fixed)` separates [page actions + Search], the bell and the profile avatar into their own capsules (≤ 3 trailing groups; Duo rail keeps bell + avatar together) | Standard bar buttons, no capsule |
| Toolbar glyphs | — | White (`BrandTokens.textPrimary`) monochrome SF Symbols | Matches the web header; accent is reserved for *state* (e.g. non-default sort = gold, active filter = accent) | Same |
| Search field | System control | `.searchable` (Songs "Filter Songs" inline; the global search sheet) | iOS 26 places it in glass automatically | Standard search bar |
| Header scrim (every page) | Content legibility | `TopEdgeScrim`: 26+ soft top scroll-edge effect + dark top gradient | Keeps titles and the first rows readable over bright artwork | Gradient only |
| Floating page tools (iPhone) | `.control`, `interactive: true` | Songs Filter/Sort and Quick Links as separate round `festivalGlassCapsule` buttons in a `FestivalGlassGroup`, trailing above the tab bar (`FloatingPageControls`, [nav-accessories.md](nav-accessories.md)) | Floating controls that react to touch; grouping lets them morph | Thin material capsules |
| Sheets / modals | System overlay | `.festivalSheet(.large / .compact)` on the sheet's root | System glass sheet forced dark; opaque when expanded | Dark `.ultraThinMaterial` + navy 62% tint |
| Menus, confirmation dialogs, context menus, alerts | System overlay | Native APIs only | Already glass | System |
| Hamburger drawer | Custom nav layer | `FestivalDrawer` (`App/Shell`), `.overlay` glass, `ConcentricRectangle` corners concentric with the display (26 pt minimum; fixed 44 pt before iOS 26), scrim masked under the panel ([app-navigation/ios.md](../../controls/app-navigation/ios.md#drawer-corners)) | Navigation surface floating over content — the canonical glass case | Frosted navy `.overlay` fallback of `festivalGlass` |
| Floating controls over content (section index scrubber, instrument selector bar, pager, "scroll to top") | `.control`, `interactive: true` | `festivalGlassCapsule(.control, interactive: true)`; wrap neighbours in `FestivalGlassGroup` | Controls that float and react to touch; grouping lets them morph | Thin material capsule |
| Song rows (Songs list, Item Shop list) | `.card` | `festivalGlass(.card, cornerRadius: 16)` per row, non-interactive | Operator request + web frosted rows over the art background. Rows are separated cards on the web, so per-row glass is faithful | `surfaceFrosted` + `.ultraThinMaterial` |
| Settings, Profile, Statistics, Suggestions, Rivals, Leaderboard *groups* | `.card` | `FestivalGlassSection("Title", subtitle:) { rows }` — **one card per group**, hairline separators between rows | Web `SectionHeader` + `FrostedCard`. One glass shape per group, never per row inside a group | Same component, frosted |
| Leaderboard/score rows inside a group | Content | Flat rows inside the group's glass card | Avoid glass-on-glass and per-row glass cost in long lists | Same |
| Chips, pills, badges, difficulty meter, FC/accuracy badges | Content | Flat opaque/tinted fills (existing Fluent tokens) | Inside glass cards; must keep exact colours and contrast | Same |
| Song Detail header, album art, charts, CHOpt images | Content | No glass | Primary content; refraction would distort it | Same |
| Status banners (paused, update failed, notices) | Content | Opaque `cardBackground` rounded rect | Warnings must be readable over any artwork | Same |
| Empty / error states (`ServiceUnavailableView`, `ComingSoonView`) | Content | Plain text on background; action button may use `.buttonStyle(.glass)` on 26 | Text is not a container | `.bordered` button |
| Primary / secondary buttons in content | Control | 26: `.buttonStyle(.glassProminent)` / `.glass`; tint accent | System button styles adopt glass correctly | `.borderedProminent` / `.bordered` |
| Sections **inside sheets** | Content | Native `Form` sections with `FestivalSectionHeader` in the header slot and `.listRowBackground(Color.white.opacity(0.06))` | The sheet is already glass; glass cards inside would be glass-on-glass | Same (the sheet is frosted) |

## Shared components (use these, not raw modifiers)

- `festivalRootChrome(session:)` (`App/Shell/RootChrome.swift`) — apply on each **tab root only**. Adds the hamburger (leading, iPhone only) and profile avatar (trailing, top-right). The profile sheet and drawer are owned by `FestivalRootView`; call `@Environment(\.openProfile)` / `@Environment(\.openDrawer)` instead of presenting your own profile sheet.
- `FestivalGlassSection(_:subtitle:content:)` (`Design/GlassSection.swift`) — titled glass card with white Title Case header outside the card, inset hairlines (iOS 18+), 44 pt minimum rows. `FestivalFootnote` for muted explanations inside.
- `festivalSheet(_:)` (`Design/SheetStyle.swift`) — dark sheet style with detents (`.large` default, `.compact` = medium + large) and a visible drag indicator. Apply to the sheet content root: `.sheet(isPresented: $x) { MySheet().festivalSheet(.compact) }`.
- `FestivalModal(_:closeIdentifier:path:onClose:content:)` (`Design/FestivalModal.swift`) — **every** modal's container (issue #23): `NavigationStack` (optionally with an `[AppRoute]` path), inline title and the system Close (`FestivalSheetCloseItem`: `Button(role: .close)` on iOS/macOS 26+, "Close" text before) top-right. Never hand-draw a ✕, a text Close/Done or a bottom Close in a modal; put extra toolbar items, `.searchable` and destinations on the content. Pair with `festivalSheet` (or the modal's own detents). HIG Toolbars: "Close dismisses a modal; prefer their standard symbols without text labels." The hamburger drawer is a side navigation panel, not a modal, and keeps its own close.
- `festivalGlass(_:cornerRadius:interactive:)`, `festivalGlassCapsule`, `FestivalGlassGroup` (`Design/GlassSurface.swift`) — the only place that calls `.glassEffect`.

## Section headers

White (`textPrimary`), `.headline`, **Title Case**, outside the card, with an optional muted `subheadline` description — i.e. `FestivalSectionHeader`. Never the system's grey uppercase list headers; set `.textCase(nil)` if a system container would upper-case them.

## Performance and verification

- Glass is not free: keep per-row glass to the shared Song row (Songs list, and the Item Shop list since issue #18: same lazy stack and bounded on-screen rows, with a far shorter feed) and measure scroll hitching with Instruments before adding it to any other long list. If hitches appear, fall back to a single group card.
- Verify each surface with `python3 tools/ios_sim.py shot` over **busy artwork** (Songs) and over the plain background (Settings); a surface that is only legible over the plain background fails.
- Reduce Transparency: with the in-app toggle on, every card, the drawer and sheets must render opaque.
