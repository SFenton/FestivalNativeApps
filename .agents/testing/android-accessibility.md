# Android accessibility results

> **What:** the Android accessibility phase: tools, what was checked on which device, findings and fixes. **Read when:** changing semantics, touch targets or colours on Android, or re-running the TalkBack/ATF passes. Tooling: [android.md](android.md#accessibility-tooling).

## Method

| Check | How | Devices |
|---|---|---|
| Accessibility Test Framework (touch targets, labels, contrast, duplicates) | Instrumented journeys (`androidTest/.../journeys/`) with ATF on every interaction and screen | FST_Phone, FST_Book_Fold (half-open) |
| TalkBack reading order and speech | `tools/android/talkback_walk.py` (real TalkBack, "next item" key chord, utterances from TalkBack's log) | FST_Phone, FST_Book_Fold |
| Touch targets ≥ 48 dp | ATF `TouchTargetSizeCheck` | as above |

## Findings and fixes (2026-09-29, FST-and-next)

| Finding | Where | Fix |
|---|---|---|
| Leaderboard rows 45 dp tall (ATF touch target) | Song Detail previews, full song board (`ScoreRow`) | Minimum height 48 dp |
| White on `#2D82E6` is 3.86:1 (ATF contrast) | Filled buttons (Settings "Show", first run Next/Done, What's New, Retry, Done, profile Select/View) | `BrandTokens.accentBlueFill` `#1A6FD8` (4.9:1) via `festivalFilledButtonColors()`; `accentBlue` stays for blue text on dark surfaces |
| Score-history rows read their summary, then every child text again | Song Detail Score History | `clearAndSetSemantics` with the summary |
| Band rows read their summary, then member names and scores again | Song Detail band previews, song band board | Inner content hidden from TalkBack |
| Chart legend read as two extra stops ("Accuracy", "Score") | Score History | Legend decorative (the chart description names both) |
| Empty-chart title and explanation are two stops | Song Detail instrument/band empty states | Merged into one stop |

ATF warnings left as is (false positives): "Tap Vocals" is an instrument name, not an instruction; "Profile: Selected Player" is the fixture player's name; duplicate speakable text for fixture rows that are identical by construction.
