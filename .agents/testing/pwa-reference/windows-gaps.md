# Installed PWA vs native Windows app: gaps

> **What:** differences between the installed PWA ([windows.md](windows.md)) and the native WinUI app at the same window presets, with a suggested fix per row. **Read when:** picking Windows parity work or reviewing a Windows surface against the PWA.

Evidence: PWA `showcase\pwa\windows\<preset>\<page>.png`, native `showcase\pwa\windows-native\<preset>\<page>.png` (compact/medium/wide, Debug build of `master` @ `e7e0521`, launched by `uiwin.py launch --route … --extra FST_SETTINGS_PATH=<empty>` so both are anonymous, live data). Native captures are `PrintWindow` stills; native motion was not recorded. Not every PWA choice should be copied: the PWA's mobile shell on desktop is a web limitation, and Windows navigation stays native ([platforms/windows.md](../../platforms/windows.md)). Rows marked **keep native** record a deliberate difference.

| # | Page / state | PWA | Native | Gap | Suggested fix |
|---|---|---|---|---|---|
| 1 | Shell, all sizes | Mobile chrome at every width: hamburger drawer, bottom tabs, FAB dock, no pinned sidebar | `NavigationView`: rail at compact, expanded pane at wide; title-bar back, hamburger, search, bell, avatar | Different navigation model | **Keep native**; match destination set and order (Songs, Leaderboards, Item Shop, Settings; Select Profile in the pane footer like the drawer) |
| 2 | Anonymous `/rivals`, `/statistics`, `/suggestions`, `/compete`, `/rivals/all` | Redirect to Songs | "No Player Selected" / "Coming Soon" / "Select a Player" pages | Native exposes player-only routes to anonymous users | Redirect to Songs (and hide the entries) until a profile is selected, or show the web's select-profile flow; decide once in `AppRouteParser` |
| 3 | `/bands` (no id) | "Band not found" empty state | Bands hub with Duos/Trios/Quads band-rankings links and a band-lookup notice | Route meaning differs | Keep the native hub only if the Bands spec adopts it; otherwise mirror the web state. TODO(orchestrator): decide |
| 4 | First run | Per-page first-run carousels on first visit + What's New after launch | None observed with a fresh settings file | Missing FRE | Wire `FirstRunCatalog` carousels per page (same slide order, 6 s demo loops) and a What's New sheet |
| 5 | Songs toolbar | Bottom FAB dock: Search pill (local filter), Sort, Quick Links; no filter for anonymous | Top toolbar: search box, `Title ↑` sort, Filter, Jump; "729 songs" count | Placement + an extra Filter for anonymous | Keep top toolbar (desktop convention); hide Filter when anonymous, keep sort options identical (Title, Artist, Year, Duration, Item Shop, Has FC) |
| 6 | Songs rows | Item Shop songs have a pulsing green/gold border (2 s loop) | No pulse observed | Missing shop pulse | Add the shop pulse (respecting reduced motion) |
| 7 | Item Shop | Large album-art grid tiles (2 per row at compact) with title overlay | List rows with cart icon | Different layout | Port the art grid (tile size from web), keep the purchase button as a secondary action |
| 8 | Song Detail header | Pinned header (art, title, artist · year · length) stays while content scrolls; View Paths in the FAB dock | Large title that scrolls away; **Paths** button under the title | Header pinning and Paths placement | Pin a compact song header on scroll; keep Paths reachable without scrolling |
| 9 | Song Detail intensity | 3×3 icon grid without labels (compact), one row at wide | Labelled vertical list | Density | Use the icon grid at compact/medium; labels via tooltip/automation name |
| 10 | Song Detail leaderboards | Instrument cards start right below intensity; two per row at wide | "Leaderboards" heading; one column | Missing multi-column at wide | Two cards per row ≥1440 epx |
| 11 | Song leaderboard rows | Score then gold accuracy badge ("100%", FC = gold) | "FC 100%" chip before the score | Order + FC treatment | Match web order and badge styling |
| 12 | Full rankings | Default metric shows total score ("107,582,999"), rows "728 / 729" | Defaults to **Adjusted** with "Top 0.13%" percentile | Default rank metric differs | Default `rankBy` to the web's default for `/leaderboards/all` (TODO(orchestrator): confirm which the spec wants) |
| 13 | Leaderboards overview | "View all rankings (868,901)" with count; two columns at wide | "View All" without count; three columns + Total Score dropdown | Missing count | Add the count to the link |
| 14 | Player History (anonymous) | Song header only, empty body | "No Player Selected" card | Empty-state wording | Match the web (or redirect) |
| 15 | Settings | Starts with App Settings; CHOpt default view as radio buttons | Profile section first, Quick Links button, dropdowns, Diagnostics | Order and control types | Order sections like the web; Diagnostics stays Debug-only |
| 16 | Drawer / pane Escape | Web drawer ignores Escape | NavigationView closes on Escape | Web bug | **Keep native** |
| 17 | Paths modal | First Escape swallowed | — | Web quirk | **Keep native** single-Escape close |
| 18 | Background | 5 s album-art cycle, 1 s crossfade, 6 s pan/zoom (10 presets); swaps art per route | Stepped-keyframe artwork background ([artwork-background](../../controls/artwork-background/windows.md)) | Motion curve and route swap not compared frame by frame | Record native with `uiwin.py` + gdigrab and compare against `compact/nav.mp4` (TODO) |
| 19 | Route transitions | Rows `fadeInUp` 400 ms ease-out, 125 ms stagger; Song Detail 300 ms / 60 ms | Not measured | Unknown | Measure native entrance timing; align to web values |
| 20 | Sheets | Bottom sheets 250–300 ms `ease` with dim | `ContentDialog`/flyouts | Presentation | **Keep native** dialogs at wide; consider bottom-sheet style at compact |
| 21 | Launch | Theme-colour splash with spinner ~0.7 s, FCP 0.5–1.2 s | Shell ~0.3 s (AOT, [platforms/windows.md](../../platforms/windows.md)) | Native faster | **Keep native** |
| 22 | Title bar | Theme colour `#1A0830`, page title in window title | Mica/dark custom title bar with search box at wide | Window title text | Set the window title to "Festival Score Tracker - <page>" for taskbar/Alt+Tab parity |

## Top gaps to schedule

1–4, 6–8, 11–14 and 18–19 above, in that order (2, 4 and 12 need an orchestrator decision first).
