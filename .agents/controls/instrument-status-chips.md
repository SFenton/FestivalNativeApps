# Selected-player instrument status chips (`fst.songs.instrument-status.*`)

Source: `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:190-200,251-271,455-535,548-549`,
`FortniteFestivalWeb/src/components/display/InstrumentIcons.tsx:38-51,93-122`,
`FortniteFestivalWeb/src/pages/songs/layoutMode.ts:14-81`,
`FortniteFestivalWeb/src/contexts/SettingsContext.tsx:55-93`,
`packages/theme/src/colors.ts:15-68` and
`packages/theme/src/spacing.ts:120-127`.
Keep this control **pending**, even when named fixture cases pass:
not every native layout, account, filter, sort and accessibility state is ported.

## Presentation and dependencies

Show one badge per **enabled** solo chart, in the service's stable nine-chart
order, only for an explicitly selected player whose public HTTP 200 scores
are available, when Show Instrument Icons is on, Songs is not filtered to
one chart and Filter Invalid Scores is off. Derive at most nine statuses
from the selected profile's existing, validated **per-song** score index.
Do not issue another GET, send selected-profile headers, cache raw profile
bytes across accounts, or enable a band search. The source never renders
these chips for bands. An available 200 with no scores is not a 202:
charted parts have "no score", and uncharted parts are unavailable.

| Source status | Native cue and spoken state | Rule |
|---|---|---|
| Not charted | Muted circle, slash; "not charted" | Song difficulty missing, nonfinite, negative or 99, **even if** a score is present |
| Full combo | Gold circle, star; "full combo" | Charted, score greater than zero and explicit FC true |
| Scored | Green circle, check; "scored" | Charted, positive score without explicit FC |
| No score | Red circle, minus; "no score" | Charted, no row or zero score without FC |
| Inconsistent FC | Red circle, exclamation; "score missing despite a reported full combo" | Charted, zero score with explicit FC true |

The last state is an **intentional safety deviation**: React colors
`fc:true, sc:0` gold because FC precedes score checking, while native's
single-chart summary calls zero "No score". The service does not guarantee
this contradictory tuple is impossible. Surface the inconsistency rather
than claiming a valid FC or rejecting the whole player profile.
Loading, 202 syncing, error and publication changes retain their existing
explicit score state **without chips**; the source's 202 red-chip behavior
is inferred from static code, not a browser observation. Filter Invalid
Scores still pauses selected score presentation until native `ml`/`vs`/`rt`
fallback selection exists; never color raw, potentially invalid scores as
though filtered. Icons off or one chart chosen retains the first-visible
or selected-chart summary with independently saved metadata toggles.
Source icons-off without a chart filter instead falls back to Lead even
when Lead is hidden; native's first-visible behavior is a documented
Settings-aware departure. Source last-played sorting can keep an extra
date beside chips; that profile-specific sort is not native yet.

## Native layout, accessibility and evidence

`SongInstrumentStatusPolicy` owns classification and mode gating in
`FestivalCore`; SwiftUI uses a measured, balanced flow with 34-point base
chips, a 48-point accessibility minimum and 64-point cap instead of a
device-width detector. Text initials are **native-drawn substitutes**, not
redistributed source PNGs; instrument-specific Keyboard/Pro Keys `sig`
variants remain pending until catalogue signature data and licensed
icons are available. Each colored circle has a distinct status mark.
The combined Song navigation link must speak every enabled chart and
status in order, without creating nine tiny independent actions; card
title, Shop badge and chart filter remain reachable. Show Instrument
Icons must stay available in Settings even without a selected player;
metadata toggles are saved but take visible effect in the icons-off or
single-chart presentation.

The generated Fluent contract shares gold/green/red fill, explicit
strokes and muted/unavailable tones across Swift/Compose/WinUI.
`python3 -m tools.contrast_gate` requires at least **4.5:1** for
glyph/mark against the opaque native fill and **3:1** for unavailable
outline and red status boundary against the card. It does **not**
establish source frosted-card or all screenshot-pixel contrast:
review actual iPhone/iPad images, large text and named accessibility
targets separately. A fixture-only WebKit comparison passes **4/4**
for icons off/on at phone/tablet widths and asserts source order,
colors and chip Y-row grouping: **five plus four** on the phone,
all nine on one tablet row. That resized WebKit
tablet is not a native iPad runtime, and neither capture certifies
native pixel parity or default first-run onboarding.

Synthetic player 1 has two non-FC Lead scores; player 2 has two FC
Lead scores plus a positive, non-FC Pulse Drums score. The mock Pulse
Drums leaderboard agrees on score, rank, FC, accuracy, season and
population, while Bass charts stay genuinely empty for the offscreen
test. Hosted Core cases cover nine-order, scored non-Lead, zero-FC,
uncharted-over-scored priority, empty scores, gates and hidden charts;
SwiftUI cases render four colors and reflow narrow/AX5 widths.
An exact serial **10/10 iPhone and 10/10 iPad** source-frozen
matrix proves real account switching, non-Lead Drums, hidden
Lead, icon toggle, filtered score, invalid-filter pause,
available-empty status and genuinely empty Bass navigation.
Normal-size iPhone selected Songs passes one unwaived `.all`
audit; named iPad text contrast and both devices' AX-size
chip-group viewport bounds pass. These named states do **not**
prove complete rendered chip-glyph contrast, iPad full `.all`,
VoiceOver order, all backgrounds/widths or pixel parity.
One private normal-size selected-player screenshot per native device
was sampled **inside** the gold/green/red/muted circles: all four
glyph/fill pairs exceeded 5.6:1 on each device (including rendered
status marks), rather than merely passing the token formula.
This one-state pixel observation is not yet an automated
all-state contrast gate.
After read-only code review, the AX-only full-width layout was
restricted to chip-visible rows, nine-status XCTest labels were
split into **exact** chart/status entries (not Drums/Pro Drums
substrings), and the zero-score FC versus no-score native marks
were checked against distinct hosted pixels. A separate
source-frozen **4/4 on each device** now verifies the changed
chip transitions, AX bounds, anonymous AX Song→Detail
navigation and fresh-launch chip isolation. The earlier
10/10 per-device matrix established broader states before
this review; do not mislabel it a post-review full run.
At AccessibilityXXXL **only for the available chip mode**,
place the title and artist at full card width, then artwork/Shop
cue, then measured chips. Anonymous, icons-off, filtered, loading,
syncing and error rows retain their existing non-chip row layout;
squeezing chip content beside artwork made the first synthetic row 872 points tall and the
second row inaccessible until scrolled. A focused iPhone case now
swipes the **named** `fst.songs.list` and requires the whole chip-group
frame above the system tab bar, not just an `isHittable` chip. That
focused path and the paired iPhone/iPad ten-case matrix pass.
Native iPad's split detail pane wraps nine chips into two
balanced rows; the source 820px WebKit viewport places nine in
one. This is an explicit platform-layout gap, not a false source
match. Keep this control `pending` until remaining gates close.
