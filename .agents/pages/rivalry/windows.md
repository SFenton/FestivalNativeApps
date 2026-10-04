# Rivalry — Windows notes

> **What:** Windows state of `/rivals/:rivalId/rivalry`. **Read when:** changing `windows/Festival.App/Pages/RivalryPage*` or `RivalryViewModel`. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Re-reads the rival detail through the session cache (usually a cache hit from Rival Detail) and shows one category (`mode`; unknown keys show the key and an empty state, as on the web).
- Native sort `ComboBox` (`fst.rivalry.sort`): Default (category order), Closest Gap, Your Biggest Leads, Their Biggest Leads, Title. The web has no sort here; the service's `sort` parameter is left at `closest`. It has a visible `Header` and UIA name "Sort By" (#203; winui-design: "Placeholder text used as the only field label → Always provide a visible label"). Title sorts by the displayed (catalogue) title, falling back to the comparison title, then the song ID (`RivalHeadToHead.Sort` title selector, #203).
- The header actions are a two-column `Grid` (Sort By `Auto`, View Profile `*`), not a horizontal `StackPanel`: a StackPanel gives the button unlimited width, so at text 200% in a compact window "View {name}'s Profile" ran off the right edge (#203). The button now trims; when the sort is hidden (empty or freeze), the button sits at the left with no gap.
- Full head-to-head rows (You | rank and score gaps | Them) in a virtualized list; below 380 epx they collapse to one line. A tied rank shows "0" while a tied score shows "+0"; this matches the web's `formatRankDelta` and score text.

## Validation (issue #203, 2026-10)

Evidence came from `a11y_matrix.py --scan --tabs 30` on the four Rivalry fixture pages: `rivalry`, `rivalry-unknown`, `rivalry-empty` and `rivalry-freeze`. A temporary wrapper without `--base-url` repeated the matrix on the live public service, with SFentonX against GingerNINZIN_JPN. The publication freeze returns 503 for rival detail, so the app rebuilds it from `rivals/all`. No selected-profile headers or blocked endpoints were used. Sizes: compact 500×800, medium 900×700, wide 1440×900 epx. The display is 3840×2160 at 150%.

| Configuration | Fixture | Live | Findings |
|---|---|---|---|
| Compact / medium / wide | ✅ Axe 0 | ✅ Axe 0 | Compact moves the actions under the title; below 380 epx rows collapse to one line |
| Maximized, snap left/right | ✅ Axe 0 | ✅ Axe 0 | — |
| Dark (app default) / light system theme | ✅ | ✅ | The app is dark-only by design (#197); light system theme leaves it unchanged |
| High contrast Night sky, Desert | ✅ Axe 0 | ✅ Axe 0 | Theme colours, no artwork, visible focus |
| Text 100% / 200% | ✅ (medium 200%: 2 edge-clip artifacts) | ✅ Axe 0 | **Fixed:** the View Profile button overflowed at compact 200%. The 2 Axe items are `BoundingRectangleSizeReasonable` on a row clipped by the viewport bottom ([windows-accessibility.md](../../testing/windows-accessibility.md) issue 3) |
| Display 100% / 150% | ✅ Axe 0 | ✅ Axe 0 | — |
| Keyboard | ✅ | ✅ | Tab order: title bar → nav → Sort By → View Profile → rows → Back (8/11/11 stops). Arrow keys move between rows, Enter opens Song Detail, Alt+Left returns |
| Narrator / UIA | ✅ | ✅ | Title is a heading. Rows are one Button stop reading "Song, Instrument, you rank N, {rival} ranks M, ahead/behind/tied". Sort By and "View {name}'s Profile" are named |

UI journeys in `rivals_journey.py`:
- `rivalry`: deep link → Sort By → Their Biggest Leads → row → Song Detail → Alt+Left back.
- `rivalry-unknown-mode`: unknown key shows the key and an empty state.
- `rivalry-empty`.
- `rivalry-freeze`: shows the status view and Retry.
- `rivalry-no-player`.

All five pass at medium. On this host, the older `populated` (hub row click → Rival Detail) and `quick-links` (pane after `resize:wide`) scenarios fail with and without the #203 changes. They don't touch Rivalry and are left for a hub follow-up.

The rival's auto-marquee artist line can be captured mid-scroll in stills. Live tie order among closest battles varies between launches as the freeze changes which charts come from `rivals/all`. The merge is deterministic for a given input.
