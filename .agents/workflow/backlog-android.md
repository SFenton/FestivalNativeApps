# Android backlog

> **What:** queued Android-only work while the Windows host is reserved. **Read when:** planning Android lanes once the host is free. Shared items: [android-windows-backlog.md](android-windows-backlog.md).

## Queue

| Item | Source | Notes |
|---|---|---|
| TalkBack walkthrough + ATF checks, every feature | Testing phase | Not started on any feature |
| Instrumented device journeys: Leaderboards, Bands, Settings, Rivals | Lane reports | Profile and Songs have them |
| Passport / tri-fold / resizable captures: Leaderboards, Rivals, Settings | Lane reports | |
| What's New sheet (web changelog, hash-gated, replay from Settings) | Cross-platform parity | Android has first run but no What's New |
| Songs: re-record the Songs → Detail → Paths video on the current build; verify "Scores unavailable" for the mock player; band sorts | and-songs2 | |
| Leaderboards: book half-open overview leaves the right side empty beside Rank History; hinge-branch test (80%); band-combo filter; selected-band spotlight | and-boards2 | |
| Bands: combo filter, Select Band Profile, Quick Links on band pages | and-bands | |
| Rivals: Rank By picker, native combo full board, half-open gap ~17 px left of the fold | and-rivals | |
| Profile: star/percentile tiles need a Songs stars filter; Global Rank opens rankings at page 1; Song Detail `?instrument=` focus; rank-history bar width (40 dp vs web 96 px) | and-profile2 | |
| Shell: floating-toolbar hide-on-scroll; embedded Song Detail pads the status bar itself; Songs filter → `RegisterPageFind`; MainActivity coverage | and-shell-search | |
| Splash uses the placeholder launcher icon; web logo needs the asset-licensing gate | and-polish | Operator approval |
| TalkBack order/touch targets + instrumented journeys for the shell changes | and-polish | |
| Delete stray empty folder `C:\c\Users\sfent\workspace\showcase\and-polish\live` on the Windows host | and-polish | Operator (safety check blocked removal) |
| Tablet permanent drawer: drop the "Festival Score Tracker" title; first entry (Songs) lines up with where the page's top content/search bar sits; transparent drawer background so the animated/song background shows through | Operator 2026-09-28 | |
| Foldables still show the large empty "Select a song" area: when width allows two columns, show **two populated columns** (auto-select the first or last-selected item); never an empty detail pane | Operator 2026-09-28 | Same rule on Duo, Windows, iPad |
| Foldable navigation rail: **top-align** the destination icons so expanding the rail into the full drawer is a natural extension of the icon positions (supersedes the earlier "vertically centre" request for foldables) | Operator 2026-09-28 | |

