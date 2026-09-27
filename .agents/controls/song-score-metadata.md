# Selected-player score metadata (`fst.songs.metadata.*`)

Source: `FortniteFestivalWeb/src/utils/songSettings.ts:66-80`,
`FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:95-135,423-480,482-500`,
`FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:43-137,215-271,393-453,508-557`,
`FortniteFestivalWeb/src/pages/songs/layoutMode.ts:81-101`,
`FortniteFestivalWeb/src/components/songs/metadata/AccuracyDisplay.tsx:13-45`,
`FortniteFestivalWeb/src/components/songs/metadata/PercentilePill.tsx:22-63`,
`FortniteFestivalWeb/src/components/songs/metadata/MiniStars.tsx:17-43`,
`FortniteFestivalWeb/src/components/songs/metadata/SeasonPill.tsx:12-36`,
`FortniteFestivalWeb/src/components/songs/metadata/DifficultyPill.tsx:8-38`,
`FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx:15-43`,
`FortniteFestivalWeb/src/components/songs/metadata/SongInfo.tsx:19-48`,
`FortniteFestivalWeb/src/components/common/MarqueeText.tsx:45-139`.
Keep the control **pending** until all documented variants, navigation
edges, widths, output shape, focus bounds and per-platform gates pass.

## Which presentation is allowed

Selected-player public scores must be `.available`, identity- and
publication-validated, and **positive** on the first enabled/explicitly
filtered chart. Show Instrument Icons off or one chart filtered selects
this presentation. Default icons-on All instruments instead shows
the separately documented [status chips](instrument-status-chips.md).
A missing chart, HTTP 200 empty/zero, 202 syncing, 403/error, failed
publication or Filter Invalid Scores pause retains the explicit
non-scored state. Do not issue a new per-row GET, send selected-profile
headers, read mutable band-search/stats/sync-status GETs, or store
raw profile bytes across a switch. A selected band has no native
Songs metadata until a guaranteed mutation-free policy exists.

## Typed source order and native safety decisions

`SongProfileCardPolicy` in `FestivalUI` projects the validated
`PlayerScore`, current catalogue `Song`/season and eight saved
switches into independent typed fields in **source default order**:
Score, Accuracy, Percentile, Stars, Season, Song Intensity and player
Game Difficulty; native Last Played follows only if present and
enabled. The first **renderable** field becomes the primary
top-trailing value. Hiding Score promotes Accuracy/FC, not the chart
name. The rest wrap right-aligned by measured available width;
large text and reduced-width iPad/macOS panes must grow rather
than clip or hide fields. The Song row remains one navigation
action, with album art and validated Shop badge separate. A
positive score on a non-Lead first-visible/filtered chart also
paints and announces a separate **Drums chart** (or corresponding
chart name) caption; do not let a Drums score look like Lead.

| Field | Native rule; source-backed or intentional departure |
|---|---|
| Score | Bold, tabular, right-aligned positive number; score 0 means **No score** rather than a successful zero-valued pill |
| Accuracy/FC | A gold, visibly/spoken **FC 97.9%** cue for explicit FC; FC only if Percentage is hidden or accuracy missing, never a fabricated `0%`. Non-FC uses `ScoreFormatting.accuracyTint` at 25% over the opaque card |
| Percentile | Source rank/total buckets, with Top 1% emphasized gold, Top 5% gold outline and ordinary neutral; absent rank/total yields no pill |
| Stars | One to five white native stars; service six is **five gold stars**, announced distinctly. At accessibility text sizes use one star plus a readable count instead of overflowing five enlarged symbols |
| Season | `S9` inverted if equal to the validated current catalogue season; old/unknown seasons keep normal contrast |
| Song Intensity | Existing seven-bar meter uses the *catalogue* chart raw value + 1; one meter per scored card, not duplicated beside the Shop badge on filtered cards |
| Game Difficulty | Player E/M/H/X tier from 0–3, separate from Song Intensity; opaque Easy/Hard require **dark** glyphs, Medium/Expert white |
| Last Played | Native currently keeps a valid saved, toggle-controlled date under Title; the source removes it under Title and injects it under Last Played sort even with its switch off. Keep this **explicit native deviation** until the missing sort/Settings migration is ready |

React's percentage-only skewed gold FC badge lacks a spoken FC label
and paints an absent accuracy as `0%`. Native deliberately makes FC
visible and spoken and never invents that percentage. CSS skew,
source 64px clipped wide row, editable metadata order and source
hidden-Lead fallback are **not** v1 goals. Preserve native's
first-visible-chart behavior; copying a possible source hidden
instrument score would undermine Settings.

## Layout, tokens and deterministic proof

Source browser captures on a 390px WebKit phone show 99,800
top-right with six remaining fields in two **3+3** rows;
at 820px they fit one trailing row. The source uses 298/322px
hysteresis for compact top placement, and the desktop threshold
changes with visible fields. Hiding Score at 820 switches the
source to an inline row, while the native first compact slice
must remain legible even without exact desktop cosmetics.
Fixture-only WebKit tests assert default order, those row groups,
FC color/italic transform and score-hidden promotion; native
row counts may differ by platform-native font/split width.
Hiding Score in the source's 820px tablet case changes its
page-level compact/inline mode, not merely the primary badge.
A separate long-title/seven-digit/Shop synthetic profile has
matched source captures at both widths: source phone marquee
clips the full title/artist and retains the score at the card's
right edge; native wraps the complete text and keeps score/Shop
reachable at AccessibilityXXXL. Source SongInfo additionally
shows **6:06** duration from `durationSeconds: 366`; native
has the typed duration but does not paint it in a Song row yet.
This and the extra native Shop action are documented geometry/
content gaps, not a parity claim.
When Last Played is present, it follows Game Difficulty and is
the **final** pill: compare its right edge with the top-trailing
Score, not the earlier Difficulty field. At AX5 compare the
wrapped date with the separate trailing Shop badge as well.
`SongMetadataFlow` must place the *actual fitted width* of an
oversized wrapped pill; reserving the entire width proposal
caused real 14pt iPhone/57pt iPad trailing gaps despite readable
content. iPad's open sidebar and Hide Sidebar give different
available widths; neither justifies a fixed number of pill rows.

The shared `fluent-tokens.json` generates Swift, Compose and WinUI
colors. `tools.contrast_gate` must keep opaque badge text at
**≥4.5:1** (dark on Easy/Hard; white on Medium/Expert)
and meaningful fill/status edges at **≥3:1**. These token
calculations do **not** prove rendered screenshot contrast;
device tests must inspect named visible pixels, text order and
score/pill right edges without a blanket accessibility waiver.
Do not add padding to the fixed Solo accuracy badge: a previous
iPad split-view iteration reproduced a serious layout loop.
The *separate* score-metadata pills use scaled horizontal text
insets: hosted xLarge, AX3 and AX5 render checks require at
least four painted glyph-to-badge-edge pixels on each side.

Targeted policy/hosted tests cover field order, Score-off promotion,
missing-accuracy FC-only, zero/empty/error, Top1/5/10, six gold
stars, current/past season and one 3/7 Lead or 5/7 Drums meter.
The distinct publication-pinned `--metadata-edge` listener on
runner-owned **8776** serves a coherent single-song catalogue,
1,234,567 player/solo score and Shop New offer without touching
shared 8765 or the empty Bass/one-shot listeners; its Python
and Swift fixture-contract checks pass. Focused **1/1 on iPhone
and 1/1 on iPad** device journeys assert score/pill trailing
alignment within 2pt, gold FC/non-FC graded badge rendered
contrast ≥4.5:1, no Shop collision and native AX5 reachability;
the iPad journey toggles Hide/Show Sidebar without a hang.
A separate serial source-frozen **10/10 iPhone + 10/10 iPadOS**
named regression matrix passed the pre-review structured player rows,
the isolated edge plus existing selected chips, genuinely empty
Bass chart, Shop/Detail and anonymous AX behavior. This is not
a 95% logic/90% UX coverage measurement or full route audit.
Later focused post-review cases passed **1/1 iPad and 2/2 iPhone**
for the dated AX5 edge, trailing pill and Settings' retained
scroll position. The subsequent source-frozen post-fix pair passed
the exact **10/10 iPhone and 10/10 iPadOS** selected/anonymous
methods; matched source WebKit comparison passed **6/6**. Both
Release builds succeed; real AppKit profile/CHOpt/Shop/selected-
Song state tests now raise merged SwiftPM logic coverage to
**1761/1843 (95.55%)** and UX to **7994/8874 (90.08%)**;
the paired iOS UI/app subset is **3166/4419 (71.65%)**.
Only the SwiftPM host categories meet their thresholds,
not the native iOS UI/app gate or complete control-state parity.
Future serial iPhone/iPad runs must retain
status-chip, anonymous, Shop, Solo and sidebar navigation
regressions. iOS 18, macOS GUI, full UX coverage, performance on
a representative catalogue, Last Played sort, source-exact
desktop layout, band cards, invalid-score substitution and the
other 24-route backlog are still open. No route is certified.
