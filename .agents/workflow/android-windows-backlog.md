# Non-Apple backlog (shared items)

> **What:** queued Android and Windows work, kept while the Windows host (`sfenton-primary`) is reserved for the operator. **Read when:** the operator frees the Windows host, planning Android/Windows lanes, or mirroring an Apple fix to the other platforms.

Status: the Windows host is **available again** (operator, 2026-09-28, batch 6); lanes take their items from these tables and tick them off in their reports; the orchestrator mirrors every operator bug cross-platform ([PROGRESS.md](../../PROGRESS.md) log has the per-batch triage). Rules that apply to every item: live-data media with SFentonX for the operator ([testing strategy](../testing/strategy.md)), fixture-only committed screenshots, [service safety](../platforms/service-safety.md), no `git reset --soft origin/master` ([windows-relay](windows-relay.md)).

## Shared items

| Item | Source | Notes |
|---|---|---|
| Changing a sort scrolls back to the top of the list | Operator batch 5 | Every sortable list (Songs, Shop, history, rankings, Rivals, Suggestions) |
| Sticky section headers with no rows visible beneath | Operator batches 3 + 5 | Android Songs headers scroll inline today; Windows grouped ListView headers are sticky — verify no show-through |
| Player profile: every per-instrument stat that is clickable on the web is clickable | Operator batch 5 | Android has tap-to-filter tiles — verify against the web list; Windows unverified. Port targets from Lane AP3's table |
| Player profile: 2-column adaptive stat grid on phone/compact, in-card chevron (›) on clickable items only | Operator batch 5 | Wider sizes 3–4 columns. Apple targets (AP3): Songs Played/FCs → Songs filtered (instrument); Best Rank → Song Detail; Total Score Rank → Full Rankings; select-first for viewed players |
| Profile push animation: mirror Lane AP3's fixes | Operator batch 5 / AP3 | Toolbar Select button present (disabled) from the first frame; loading placeholders at final size (global rank, Rank History); stable tile identity; charts built only near the viewport; close search sheet before pushing |
| Live-data screenshots/video of every feature (SFentonX) for the operator | Operator 2026-09-28 | Earlier Android/Windows media were fixture-only |
| Curated native changelog for What's New (drop web-only items) | Orchestrator recommendation | Pending operator decision; Apple ships the web text verbatim today |
| Optional: fade-in on Settings / first run / What's New | Operator question | Pending operator decision |
| Mirror Apple chrome decisions as they land | Lanes A2/AM | Larger collapsed page title; top scroll-edge scrim over artwork; sheets open full height; Sort sheet with inline ↑/↓ purple toggles and "Sort By" title; background crossfades to song art (no grow); no transition stutter/jitter; no bottom bounce at list end |
| Add `tools/android/tests`, `tools/windows/tests`, Windows a11y matrix to CI | win-infra / win-a11y | Blocked on GitHub Actions billing |

Platform-specific queues: [backlog-android.md](backlog-android.md) · [backlog-windows.md](backlog-windows.md).

## Operator batch 6 (2026-09-28) — cross-platform matrix

`W` = reported on Windows, `A` = reported on Android, `G` = general. Columns say where it (probably) applies; each lane verifies on its platform and records repro/no-repro.

| # | Item | Src | Apple | Android | Windows |
|---|---|---|---|---|---|
| 6.1 | Quick jump (#–Z / SemanticZoom) must be dismissible without picking (Esc, click outside, Back) | W | check scrubber | check index | ✔ |
| 6.2 | Hover/press highlights the **whole** song row in Search results | W | – | ripple bounds | ✔ |
| 6.3 | Anonymous Songs rows too tall (dead space below) vs Search rows | W | check | check | ✔ |
| 6.4 | App-wide pass: excess left inset on cards/rows (Search results, Leaderboards, etc.) | W | check | check | ✔ |
| 6.5 | Cards with multiple entries need row separators | W | check | check | ✔ |
| 6.6 | Chrome text (Back, hamburger, app title) white, not gray | W | check | check | ✔ |
| 6.7 | First run: one-page guide shows only **Done** (no disabled Back, no Skip); **Next/Done before Back**; no extra left/right arrows on the modal; **white** pager dots; clicking outside dismisses and only the pages actually seen count as "don't show again" | W | ✔ | ✔ | ✔ |
| 6.8 | Leaderboards: "Bands" header larger than the Duos/Trios/Quads headers | W | ✔ | ✔ | ✔ |
| 6.9 | Item Shop: art not loading; songs currently in the shop not prioritised; cards don't look like web Item Shop cards | W | check | check | ✔ |
| 6.10 | Switching List ↔ Grid view re-runs the fade/stagger correctly for the new layout | W | check | check | ✔ |
| 6.11 | Settings: "Enable Independent…" shows its sub-metadata card directly (no dropdown); that card and CHOpt Column Order are **drag-to-reorder** like the web | W | ✔ | ✔ | ✔ |
| 6.12 | Filter Invalid Scores: add tests; on prod it should filter many scores from **Winterfest Wish (Lead)** | W | ✔ | ✔ | ✔ |
| 6.13 | Settings label "Game Difficulty" → "Difficulty" (web) | W | ✔ | ✔ | ✔ |
| 6.14 | What's New: Dismiss centred horizontally; modals dismiss on outside click/tap | W | ✔ | ✔ | ✔ |
| 6.15 | Remove "Check Score Publication" (web has none); live **Service Info** card like the web | W | ✔ | ✔ | ✔ |
| 6.16 | First Run Guides: no slide counts; "Show" is a blue button like the web | W | ✔ | ✔ | ✔ |
| 6.17 | Licenses: "View Licenses" styled like web; Licenses page centred/sized like other pages; license cards show clickability (hover not transparent on Windows); Close centred; **remove the Bundled Assets section and the Iconography entry** | W | ✔ | ✔ | ✔ |
| 6.18 | Profile: "Deselect Profile" red tint like web; Overview entries centred or split into full-width cards (like iOS); **Percentiles** own card; **Rank History** own card (web pattern) | W | ✔ | ✔ | ✔ |
| 6.19 | Vertical nav rail: no translucent background | A | – | ✔ | check pane |
| 6.20 | Scrolling adds a translucent background behind the header | A | check | ✔ | check |
| 6.21 | Search modal shrinks while typing; search progress is a ring (not a line) unless the platform standard says otherwise; Songs/Players/Bands scope more pill-like if native allows; remove "N songs, X players" text | A | check | ✔ | check |
| 6.22 | "Recent Snapshots" wording; "See All" white with a chevron | A | check | ✔ | check |
| 6.23 | Notification badge clipped (phone) | A | check | ✔ | done |
| 6.24 | Quick Links icon too small for its circle | A | check | ✔ | check |
| 6.25 | Rank History chart: SFentonX Lead shows #4 as the "highest value" — match the web's axis orientation/scale | A | check | ✔ | check |
| 6.26 | Break content out of one big card into separate cards like the web (profile etc.) | A | ✔ | ✔ | ✔ |
| 6.27 | Paths: render notes and Overdrive like web; no path text / max score at the top; Karaoke notice is a native dialog | A/G | ✔ | ✔ | ✔ |
| 6.28 | Sheets extend to the very top even though the grabber sits well below the camera | A | check | ✔ | – |
| 6.29 | "View full leaderboard" transparent/different style — one consistent purple button everywhere | A | check | ✔ | check |
| 6.30 | Global instrument leaderboards: pagination closer to web; selected-player row UX above the page navigator | A | check | ✔ | check |
| 6.31 | Intensity card 2-column on unfolded/tablet, multiple instruments in 2 columns; handle half-fold and full unfold | A | iPad later | ✔ | check wide |
| 6.32 | Songs filter must match the web (why is difficulty a slider?) | A | check | ✔ | check |
| 6.33 | Empty states ("No songs") vertically centred like web | A | check | ✔ | check |
| 6.34 | Notifications modal matches web (art, icons) | A | check | ✔ | check |
| 6.35 | Percentile rows clickable → Songs filtered like web | G | ✔ | ✔ | ✔ |
| 6.36 | Port the web **Instrument Selector** (all its modes/capabilities) | G | ✔ | ✔ | ✔ |
| 6.37 | Suggestions filter respects/reflects enabled instruments from Settings | G | ✔ | ✔ | ✔ |
| 6.38 | Song instrument cards: drop the "Your score…" text | G | ✔ | ✔ | ✔ |
| 6.39 | Score history lives **on the song page** like the web, not a separate page | G | ✔ | ✔ | ✔ |
| 6.40 | Song page header scrolls away (Android) like iOS; header has album art + subtitle | G | done | ✔ | check |
| 6.41 | Pages must not appear before content is ready: spinner until ready, then fade, then staggered content (web pattern) | G | ✔ | ✔ | ✔ |
| 6.42 | Selected-player rows use the web's bolding | G | ✔ | ✔ | ✔ |

