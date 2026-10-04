# Rival Detail — Windows notes

> **What:** Windows state of `/rivals/:rivalId`. **Read when:** changing `windows/Festival.App/Pages/RivalDetailPage*` or `RivalDetailViewModel`. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Reads the scope carried on the route (leaderboard, combo or per-chart merge; no scope merges every visible chart). Summary line = web `rivals.detail.summary`.
- Web categories via `RivalCategorization` (same keys, thresholds and descriptions) in masonry cards; 5 compact song rows each, "View All N Songs" (singular "View 1 Song") → Rivalry with the same scope. Headings are tinted by sentiment.
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
