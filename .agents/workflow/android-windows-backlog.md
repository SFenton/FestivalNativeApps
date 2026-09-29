# Non-Apple backlog (shared items)

> **What:** queued Android and Windows work, kept while the Windows host (`sfenton-primary`) is reserved for the operator. **Read when:** the operator frees the Windows host, planning Android/Windows lanes, or mirroring an Apple fix to the other platforms.

Status (2026-09-28): the operator asked that **no new work start on the Windows host** after the lanes running at the time finished (FST-and-polish, FST-win-pwa). Add items here instead of launching lanes; the orchestrator mirrors every operator bug cross-platform ([PROGRESS.md](../../PROGRESS.md) log has the per-batch triage). Rules that apply to every item: live-data media with SFentonX for the operator ([testing strategy](../testing/strategy.md)), fixture-only committed screenshots, [service safety](../platforms/service-safety.md), no `git reset --soft origin/master` ([windows-relay](windows-relay.md)).

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
