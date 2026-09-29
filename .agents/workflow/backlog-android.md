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
| FST-and-polish leftovers | and-polish report | Fill in when its report lands (splash, CHOpt drag, spinners/marquee in closed lanes' files) |
