# Rival Detail — Windows notes

> **What:** Windows state of `/rivals/:rivalId`. **Read when:** changing `windows/Festival.App/Pages/RivalDetailPage*` or `RivalDetailViewModel`. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Reads the scope carried on the route (leaderboard, combo or per-chart merge; no scope merges every visible chart). Summary line = web `rivals.detail.summary`.
- Web categories via `RivalCategorization` (same keys, thresholds and descriptions) in masonry cards; 5 compact song rows each, then the shared purple **View All** button (`FSTViewAllButtonStyle`, label and name from `ViewAllCta`; spoken "View All, <category>", ID `fst.rival-detail.category.<key>.view-all`) → Rivalry with the same scope. Headings are tinted by sentiment.
- Rule (#321): a category card ends with the [view-all-cta](../../patterns/view-all-cta.md) button (R6/R7), never an in-card text link, and the copy is "View All", never "See All" (`section-headers/windows-view-all-copy` guard). It replaced the blue "View All N Songs" `HyperlinkButton`; the count went with it, as on Apple and the web card header (`common.viewAll`). Tests: `ViewAllCtaTests` (consumer list, no overrides), `RivalsViewModelTests.RivalDetail_*`, `rivals_journey.py` `populated` (name, type, invoke), `kb-rival-detail-compact` (Tab from the rows lands on the button).
- View Profile opens `AppRoute.Player(rivalId)`. Song rows open Song Detail on the compared chart; titles/art come from the catalogue when loaded.
- Header below 640 epx (`Narrow`): View Profile drops under the summary beside the compact-only Quick Links menu. Both are at least 40 epx tall (`FSTMinTargetSize`, issue #72). The profile label is in a `Grid` so it wraps rather than clipping at 200% text.

## Validation (issue #202, 2026-10)

These checks ran with `a11y_matrix.py --only rival-detail --scan --tabs 30` against the fixture, plus a live-service run with SFentonX. Axe.Windows found 0 errors in every configuration. Tab stops were 12 compact and 14 medium/wide, with none outside the app and none repeated.

| Configuration | Result |
|---|---|
| Compact / medium / wide; snapped left/right; maximized | Pass. Compact stacks the header and shows the Quick Links menu; from medium, View Profile sits top-right and the cards use masonry columns |
| Light / dark system theme | Pass. Both look the same because the app is dark-only, a documented deviation ([design/windows.md](../../design/windows.md)) |
| High contrast (Aquatic, Night Sky) | Pass. Pills lose their fill, and the sign and bold text carry the meaning. System colours are used |
| Text 200% | Fixed: the compact View Profile label clipped mid-letter (a horizontal `StackPanel` gave it infinite width, so the ellipsis never applied). It now wraps |
| Display 100% / 150% | Pass |
| Keyboard | Fixed: on compact screens, Tab reached Quick Links before View Profile, which sits to its left. View Profile is now declared first (`kb-rival-detail-compact` journey). Order: title bar → View Profile → Quick Links (compact) → rows → View All per card. Focus is visible throughout |
| Narrator / UIA | Fixed: Quick Links menu items were Toggle-only, so Narrator's default action didn't jump ([quick-links/windows.md](../../controls/quick-links/windows.md)). Cards are named groups, category titles are Level 2 headings and rows have full names |

The compact song row also had a double space ("you ·  #30") from XAML `Run` whitespace, now fixed. Journeys: `rivals_journey.py` `populated`, `freeze`, `no-player`, `detail-empty` (no shared songs) and `detail-nav` (Quick Links jump via UIA Toggle → song row → Song Detail → Back → View Profile → Player → Back).

## Validation (issue #284, 2026-10)

Re-validation of the #95 fix ("Rivals screens don't load") on the live public service with SFentonX → That_Man_1_2_3_4 (`journeys/a11y-rival-detail-live.json`: `rd-live` deep link, all visible charts; `rd-live-flow` Rivals → Lead View All → All Rivals → rival → Closest Battles View All → Back). Every rival detail read answered 200 (no freeze 503), and the page showed "515 shared songs · 190 ahead / 325 behind" and its category cards. Axe.Windows found 0 errors in every configuration; Tab walks had no stops outside the app and no repeats.

| Configuration | Result |
|---|---|
| Compact / medium / wide; maximized; snapped left/right | Pass. Compact stacks View Profile beside Quick Links; from medium the cards use masonry columns |
| Light / dark system theme (with display 150% / 100%) | Pass. They look identical (dark-only app, documented deviation) |
| High contrast (Desert) | Pass. Pills drop their fill; sign and bold carry the meaning; View All uses the system highlight |
| Text 200% | Pass. Title, summary and the View Profile label wrap; the row's rival name ends in an ellipsis on compact, while the row's UIA name keeps it whole |
| Display 100% / 150% | Pass |
| Keyboard | Pass (`kb-rival-detail-compact`). Order: title bar → View Profile → Quick Links (compact) → each card's rows (one Tab stop; arrow keys move between rows, XY focus) → that card's View All. A song in two categories (e.g. Closest Battles and Almost Passed) is two tab stops with the same AutomationId, as on the web (`RivalCategorization` overlaps) |
| Narrator / UIA | Pass. Rows read "<song>, <chart>, you rank N, <rival> ranks M, they lead/you lead"; View All reads "View All, <category>". The loading ring reads "Busy Loading" (ProgressRing peer) and now has the ID `fst.rivals.page-loading` |
| Load and recovery (fixture) | Covered by `rivals_journey.py` `detail-loading`, `detail-retry` (generic 500 → manual Retry, no countdown → cards), `detail-freeze-fallback` (every detail read a freeze 503 → page rebuilt from `rivals/all`, no status) and the existing `freeze` countdown; Axe scans by the `rival-detail-error`, `rival-detail-freeze` and `rival-detail-fallback` pages in `journeys/a11y.json` |

Design review (`winui-design`): the ring is a bare `ProgressRing` while the layout guidance asks for "progress text or skeleton; not just a spinner with no context". It's kept deliberately: [load-transition](../../patterns/load-transition.md) R1 is one spinner, as the web `LoadGate`, and the ring's UIA name gives Narrator the context. The error state follows the guidance ("cause if known + a retry/repair affordance; never colour-only") through the shared service-status view.
