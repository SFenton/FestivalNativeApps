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
| Header scrim (every page) | Content legibility | `TopEdgeScrim`: 26+ soft top scroll-edge effect + dark top gradient ending 32 pt below the bar (max 150 pt; #286) | Keeps titles and the first rows readable over bright artwork | Gradient only |
| Top-bar page tools (iPhone, issue #92) | System toolbar glass | Sort, Filter, Quick Links as standard trailing bar items in one glass group, then bell and avatar in a second (`ToolbarSpacer(.fixed)`); the floating dock above the tab bar is gone ([nav-accessories.md](nav-accessories.md)) | System chrome over custom floating controls (rule 1) | System bar material |
| Sheets / modals | System overlay | `.festivalSheet(.large / .compact)` on the sheet's root | System glass sheet forced dark; opaque when expanded | Dark `.ultraThinMaterial` + navy 62% tint |
| Modal header fade | Content legibility | `ModalTopEdgeFadeModifier` (in `FestivalModal`): content alpha-fades to transparent behind the header (top safe-area inset; last ≤24 pt ramps back in) so the sheet's own background shows through (issue #94) | Keeps the title and Close clear of scrolled rows and the white Paths image; no dark overlay, so it works on glass, frosted and opaque sheets | Same |
| Menus, confirmation dialogs, context menus, alerts | System overlay | Native APIs only | Already glass | System |
| Hamburger drawer | Custom nav layer | `FestivalDrawer` (`App/Shell`), `.overlay` glass, `ConcentricRectangle` corners concentric with the display (26 pt minimum; fixed 44 pt before iOS 26), scrim masked under the panel ([app-navigation/ios.md](../../controls/app-navigation/ios.md#drawer-corners)) | Navigation surface floating over content — the canonical glass case | Frosted navy `.overlay` fallback of `festivalGlass` |
| Floating controls over content (section index scrubber, instrument selector bar, pager, "scroll to top") | `.control`, `interactive: true` | `festivalGlassCapsule(.control, interactive: true)`; wrap neighbours in `FestivalGlassGroup` | Controls that float and react to touch; grouping lets them morph | Thin material capsule |
| Song rows (Songs list, Item Shop list) and leaderboard rows (`RankingRowSurface`) | Content (material) | `festivalRowCard(cornerRadius: 12)` (`Design/RowCardSurface.swift`): `ultraThinMaterial` + fitted tint + 1 pt rim, tuned to look like the tinted glass card it replaced (operator, 2026-10-03; see [Song row card](#song-row-card)) | Web frosted rows over the art background; separated cards like the web. A live `glassEffect` per row cost ~30% of a row's main-thread build, and HIG Materials puts content on standard materials | `surfaceFrosted` + `.ultraThinMaterial` (unchanged) |
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
- `FestivalModal(_:closeIdentifier:path:onClose:content:)` (`Design/FestivalModal.swift`) — **every** modal's container (issue #23): `NavigationStack` (optionally with an `[AppRoute]` path), inline title and the system Close (`FestivalSheetCloseItem`: `Button(role: .close)` on iOS/macOS 26+, "Close" text before) top-right. Never hand-draw a ✕, a text Close/Done or a bottom Close in a modal; put extra toolbar items, `.searchable` and destinations on the content. Pair with `festivalSheet` (or the modal's own detents). Its content fades out under the header (`ModalTopEdgeFadeModifier`, issue #94); a sheet that builds its own `NavigationStack` (the feedback form) or pushes pages inside a modal (Find Rival) applies the same modifier. Measure the header as the larger of the content's top safe-area inset (read on a safe-area-respecting background: a mask's geometry, and any view that ignores the safe area, reports a zero inset) and its offset below the container (read in a named coordinate space; global frames include the sheet transform). Never add them: Paths content sits below the bar yet still reports the full inset (iOS 26.5). HIG Toolbars: "Close dismisses a modal; prefer their standard symbols without text labels." The hamburger drawer is a side navigation panel, not a modal, and keeps its own close. **Exception:** the feedback form ([feedback-form](../../controls/feedback-form/ios.md)) is a scoped task that can lose typed input, so it uses Cancel (leading) and Submit (trailing) with a discard confirmation instead of Close (HIG Sheets: "Single-view sheets: Cancel on the top toolbar's leading edge; Done, when present, trailing.").
- `festivalGlass(_:cornerRadius:interactive:)`, `festivalGlassCapsule`, `FestivalGlassGroup` (`Design/GlassSurface.swift`) — the only place that calls `.glassEffect`.
- `festivalRowCard(cornerRadius:)` (`Design/RowCardSurface.swift`) — the Song row's material card (Songs, Item Shop list). Same accessibility fallbacks as `festivalGlass(.card)`.

## Section headers

White (`textPrimary`), `.headline`, **Title Case**, outside the card, with an optional muted `subheadline` description — i.e. `FestivalSectionHeader`. Never the system's grey uppercase list headers; set `.textCase(nil)` if a system container would upper-case them.

## Performance and verification

- Glass is not free: no per-row `glassEffect` in long lists. Per-row glass also skipped the rows' staggered load-in fade, so the non-glass selected-player row faded in last (issue #295); leaderboard rows now share the material row card too. The Song row uses the material [row card](#song-row-card); any other long list uses one group card (`FestivalGlassSection`) or flat rows. Measure with `tools/apple_perf.py --stress` before adding a per-row surface.
- Verify each surface with `python3 tools/ios_sim.py shot` over **busy artwork** (Songs) and over the plain background (Settings); a surface that is only legible over the plain background fails.
- Reduce Transparency: with the in-app toggle on, every card, the drawer and sheets must render opaque.

## Song row card

Operator decision 2026-10-03: a cheaper Songs row card with the same look (Lane CARD). HIG `materials.md`: "**Don't use Liquid Glass in the content layer.** Use standard materials for content-layer elements such as app backgrounds"; a Song row is content, so the row moved from tinted Liquid Glass to a standard material.

| Layer | iOS / iPadOS 26+ | macOS 26+ |
|---|---|---|
| Material | `.ultraThinMaterial` (app scheme: dark) | same |
| Tint above it | sRGB (15, 17, 23) at 68% (88% with system Increase Contrast) | neutral (138, 135, 138) at 17% |
| Rim | 1 pt `strokeBorder`, white 14% → 3% top to bottom | white 6% → 0% (glass shows almost no edge) |
| Reduce Transparency (system or in-app), in-app Increase Contrast | opaque `cardBackground` + `borderSubtle` (pixel-identical to the glass card's fallback) | same |
| iOS 17–25 / macOS 14–25 | `surfaceFrosted` + `.ultraThinMaterial` + `glassBorder` (unchanged) | same |

- **Fitted, not guessed.** The Debug A/B switch `FST_DEBUG_ROW_CARD_AB=<file>` draws the old glass card while the file says `glass`; flip it between two window captures with `FST_DEBUG_STILL_BACKGROUND=1` for pairs over an identical backdrop. iOS glass stays dark over the dimmed artwork (`cardBackground` as the tint read ~8 levels too blue); macOS glass reads lighter than its backdrop, so the Mac uses a light veil instead.
- **Plain modifiers only.** Material, tint and rim are three `background(_:in:)`/`overlay` modifiers; the same layers inside a nested `.background { … }` builder cost about as much as the glass. Tint and rim are free (iPad sim: material only 8.63 ms/row, + tint 8.70, + rim 8.64).
- **Cost:** see [architecture.md § Performance](../../platforms/apple/architecture.md#performance) (iPad −15%, iPhone −11%, Mac −8% main-thread time per row built; Mac stress stalls about halved).
- **Known difference (macOS, bright art):** Liquid Glass passes more of the artwork's brightness and detail through than the thinnest material. Over the brightest, most colourful covers the Mac card reads up to ~15 levels darker and more frosted; over dark covers ~6 levels lighter (mean error over 8 backdrops < 1 level). iOS/iPadOS pairs differ by 1–3 levels. Evidence: `~/FestivalShowcase/native-perf/card/`.
- System Increase Contrast (no in-app toggle): Liquid Glass darkens itself by 6–8 levels, so the iOS/iPadOS card uses an 88% tint there (pairs within 2–3 levels); the row still adds its own white 2 pt outline. The Mac keeps its veil (the system setting is not toggled on this host).
- First-run demo replicas of the row (`FirstRunNativeSongsDemos`) keep `festivalGlass(.card)`: a handful of rows in a sheet, no scrolling cost.
- 2026-10-04 (operator): the material Songs row card (`Design/RowCardSurface.swift`) is accepted on all Apple platforms, including the Mac's darker/more frosted look over bright covers; don't revert to per-row Liquid Glass.

