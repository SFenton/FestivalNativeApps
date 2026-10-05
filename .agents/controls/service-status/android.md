# Service status — Android notes

> **What:** Compose implementation, validation and evidence. **Read when:** showing a failed read on Android. Spec: [spec.md](spec.md).

## Implementation

- `ServiceIssue.from(error)` (core) + `RetryingLoader` (presentation): scrape freeze counts down from `Retry-After` with `ServiceRetryBackoff` (30→60→…→300 s) and retries itself; other issues wait for Retry. A newer load cancels an older one. `FST_DEBUG_FORCE_FREEZE=1` freezes each API path once (`ForcedFreezeTransport`); the shell's startup catalogue read uses up the Songs freeze, so validate on a pushed route such as `fullRankings:Solo_Guitar` or `leaderboards`.
- `ui/common/ServiceStatus.kt` `ServiceStatusView` (full page): a polite live region holding the icon, heading (`titleLarge`, `heading()`, `fst.service-status.title`), message, countdown (`m:ss`, gold, `fst.service-status.countdown`) and a 48 dp `FilledTonalButton` (`fst.service-status.retry`, "Retry Now" / "Retry").
  - Icon per issue, mirroring the iOS symbols (`serviceStatusIcon`): Sync, CloudOff, HourglassTop, SearchOff, WifiOff, WarningAmber, 40 dp, decorative. Gold while retrying automatically, otherwise primary text (`serviceStatusIconTint`).
  - Pulse (alpha 1 → 0.4, 1 s, reversing) only while retrying automatically and never under Reduce Motion: system animator scale 0 or the in-app toggle (`serviceStatusPulses`, `LocalFestivalAccessibility`).
  - Separating hinge (book or tabletop half-open; `rememberHingeSide` + pure `hingeSidePadding`): the page sits on the hinge's wider side (leading on a tie), or below a tabletop fold like `festivalSheetHingeSide`. Material 3: "Never place interactive content or critical information across the hinge area." Flat folds keep the centred page.
  - Short viewport (< 320 dp inside the shell padding, `isCompactStatusHeight`; phone landscape is ~220 dp): no icon and tighter spacing, so Retry stays above the bottom bar. Content still scrolls (200% type in landscape).
- `ServiceStatusInline` (`fst.service-status.inline`, no live region, `TextButton` Retry ≥ 48 dp with an optional host tag): heading `labelLarge`, then the countdown or message `bodySmall`. The countdown speaks `countdownLabel` ("Trying again automatically in N seconds"). From 1.5× font scale (`inlineStacks`) Retry moves under the text, as on iPhone. `onRetry = null` hides Retry (Global Search players section, #299) at every scale.

## Validation (issue #140, 2026-10-04)

Forced freeze (`FST_DEBUG_FORCE_FREEZE`) on `fullRankings:Solo_Guitar` (full page) and `leaderboards` (inline rows), dark theme (the app is dark-only, so light system theme renders identically), animator scale 0 unless noted:

| AVD / posture | Width | Checked | Finding |
|---|---|---|---|
| FST_Phone portrait | compact | font 1.0 / 2.0, TalkBack, live offline | OK after fixes: inline rows stack Retry at 2.0 (was squeezed) |
| FST_Phone landscape | compact, ~220 dp tall | font 1.0 / 2.0 | Fixed: Retry was under the bottom bar; compact page now fits at 1.0 and scrolls to Retry at 2.0 |
| FST_Tablet landscape / portrait | expanded / medium | font 1.0 / 2.0 | OK; inline rows stack at 2.0 |
| FST_Resizable phone / foldable / tablet / desktop | compact → expanded | font 1.0, desktop at 2.0 | OK; foldable preset's flat fold keeps the centred page |
| FST_Book_Fold folded / unfolded | compact / medium | font 1.0, unfolded at 2.0 | OK |
| FST_Book_Fold half-open | separating vertical fold | font 1.0, device test | Fixed: page straddled the fold; now on the wider side |
| FST_Passport_Fold folded / unfolded | compact / expanded | font 1.0 | OK |
| FST_Passport_Fold half-open | separating vertical fold | font 1.0, device test | Fixed: same straddle; now on the wider side |
| FST_TriFold folded / partial / unfolded | compact → expanded, flat folds | font 1.0, folded at 2.0 | OK; inline rows stack at 2.0 |

`device.py` launches on logical display 0; on FST_TriFold an `am start` without `--display 0` lands on the always-on cover region (display 2), so pass it in custom drives.

Accessibility:
- TalkBack (FST_Phone, live log): the full page announces once on appearance, "Scores are updating. New scores are being published. This page will try again automatically. Trying again automatically in 29 seconds. Retry Now. Button"; the per-second countdown doesn't re-announce. Inline rows are silent; linear order is heading, countdown label, Retry Now per card.
- Touch targets: Retry ≥ 48 × 48 dp on both variants (tests). Contrast on the dark-only theme: white on the tonal button ~11.8:1, `accentBlue` text button on `cardBackground` ~4.9:1, gold and `textSecondary` on the app background well above 4.5:1.
- Reduce Motion: device captures run at animator scale 0 and show a static icon; `--animations` shows the gold pulse.
- Font 2.0: full page wraps and scrolls; inline rows stack Retry under the text.

## Fixed in #140

- Inline countdowns spoke "Trying again in 0:30"; they now speak "Trying again automatically in 30 seconds" (spec).
- One hourglass/cloud icon for every issue and no pulse; now one icon per issue and a gold pulse that Reduce Motion removes (closes the open Reduce Motion item).
- Font 2.0 on phones squeezed inline headings to a word or two beside "Retry Now"; Retry now stacks under the text.
- Book Fold and Passport Fold half-open centred the full page's heading, message and Retry across the hinge; the page now stays on one side of a separating fold.
- Phone landscape put the full page's Retry under the bottom navigation bar; short viewports now drop the decorative icon.

## Material 3 deviations (deliberate)

Reviewed against the `material-3` skill (Compose): `FilledTonalButton` ("Medium emphasis") for the page's only action and `TextButton` ("Lowest emphasis. Inline actions") for section rows; ~48 dp targets; verified contrast.
- Brand tokens (gold countdown, dark-only scheme) instead of colour-scheme roles: the cross-platform spec mandates them, so the skill's "hardcode colors" anti-pattern doesn't apply.
- The compact-height check measures the control's own viewport with `BoxWithConstraints` instead of the window size class: the control is embedded at 360 dp (Bands), in split panes and under shell bars, which the window class can't see.
- No numeric count transition: the countdown stays one plain text node so TalkBack reads one label.
- Flat folds (unfolded book/passport, tri-fold panels, resizable foldable) keep the centred page: they have no physical gap, and the app's sheets and Band layouts also only move for a separating hinge.

Live-service evidence: only `offline` is reachable without fixtures (network disabled on the emulator), so it covers the phone (portrait, landscape, font 2.0, inline rows), Book Fold half-open and Retry recovering once the network returns. Freeze, unavailable, syncing, not-found and other were validated with the forced freeze and tests only.

## Tests

- `ServiceStatusUiTest` (Robolectric): every state — `scrape-freeze-countdown` (clock, spoken label, Retry Now click, live region), `scrape-freeze-retrying` (backed-off 1:00), `unavailable` with and without `Retry-After`, `offline`, `syncing`, `not-found`, `other`, `inline` (silent, spoken label, manual state, no-Retry variant) — plus icons, tint, pulse rule, reduced motion, compact height, font 2.0 (full page fits, inline stacks) and hinge placement (`hingeSidePadding`, book and tabletop).
- `ServiceStatusDeviceTest` (connected, ATF): every full-page state's reading order (heading → message → countdown label → Retry), live region present, 48 dp Retry; inline rows silent in order; font scale 2 keeps parts on screen and stacks inline Retry. Passed on FST_Phone, FST_Tablet, FST_Book_Fold (unfolded and `--posture half`), FST_Passport_Fold (`--posture half`) and FST_TriFold; the full-page test also asserts nothing straddles a separating fold.
