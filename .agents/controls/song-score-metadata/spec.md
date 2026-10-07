# Selected-player score metadata (`fst.songs.metadata.*`) — spec

> **What:** which selected-player fields a Songs row shows, in what order and style, and where natives deliberately differ. **Read when:** changing the icons-off / single-chart selected-player row on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/utils/songSettings.ts:66-80`, `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:95-135,423-480,482-500`, `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:43-137,215-271,393-453,508-557`, `FortniteFestivalWeb/src/pages/songs/layoutMode.ts:81-101`, `FortniteFestivalWeb/src/components/songs/metadata/AccuracyDisplay.tsx:13-45`, `FortniteFestivalWeb/src/components/songs/metadata/PercentilePill.tsx:22-63`, `FortniteFestivalWeb/src/components/songs/metadata/MiniStars.tsx:17-43`, `FortniteFestivalWeb/src/components/songs/metadata/SeasonPill.tsx:12-36`, `FortniteFestivalWeb/src/components/songs/metadata/DifficultyPill.tsx:8-38`, `FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx:15-43`, `FortniteFestivalWeb/src/components/songs/metadata/SongInfo.tsx:19-48`, `FortniteFestivalWeb/src/components/common/MarqueeText.tsx:45-139`.

## When this presentation applies

Selected-player scores are available, identity- and publication-validated, and **positive** on the first enabled / explicitly filtered chart, **and** Show Instrument Icons is off or one chart is filtered. Default icons-on "All instruments" uses [status chips](../songs-instrument-status-chips/spec.md). Missing chart, 200 empty/zero, 202, 403/error, failed publication or the Filter Invalid Scores pause keep an explicit non-scored state. No per-row GET, no selected-profile headers, no blocked reads, no raw profile bytes kept across a switch. Selected bands have no metadata until a mutation-free policy exists.

## Wide rows: the profile panel

On wide shells (Apple: iPad, the iPhone Duo inner display and Mac), with a player selected, a Songs row that is at least 600 pt wide (the regular-width breakpoint) splits into two equal halves inside its one row card. The song stays on the left (art, title line, Shop icons and, with icons on, the [status chips](../songs-instrument-status-chips/spec.md)). The right half holds one flat card per **scored** chart (Settings-visible, charted, score > 0): the chart icon, then that chart's pills from this spec in the saved Settings order.
- **Fields.** "All instruments" cards show only Score, Accuracy/FC, Percentile and Stars, each where enabled. A filtered chart's single card shows every enabled field and wraps.
- **Columns.** Cards use equal columns and keep their pills on one line. The panel takes the most columns that fit. All-instruments cards drop Stars only when that saves a line (`SongProfilePanelPolicy.arrangement`). VoiceOver still hears the Stars.
- **When the row stays plain.** These keep today's row and its states:
  - no profile;
  - no scored chart on the shown charts;
  - a row narrower than 600 pt;
  - a loading, syncing, failed or publication-paused score index;
  - Filter Invalid Scores;
  - accessibility text sizes;
  - an invalid accuracy value;
  - Item Shop rows.
- **Grid.** The panel never invents a load transition (load-transition: existing Songs reveal only). While a player is selected (and Filter Invalid Scores is off), the landscape grid shows one song per row so each row has the width.
- **Shells.** iPad, the iPhone Duo inner display and the Mac opt in (`songRowsAllowProfilePanel`). iPhone and folded Duo are unchanged.
- **Surfaces.** Instrument cards are flat `surfaceMuted` 35 % fills with an 8 pt radius (a stroke under Increase Contrast) inside the row card ([surface-materials](../../patterns/surface-materials.md) R6). There is no second material.
- **Accessibility.** Each card is one VoiceOver element ("Lead: Score 270,007, Full combo, accuracy 100 percent, …"), and the row stays one combined link.
- **Test IDs.** `fst.songs.profile-panel.<songId>` and `fst.songs.profile-panel.<songId>.<instrument>`.
- **Selected band.** When band selection ships, the right half shows the band's score card(s) instead. Apple has no band selection yet, and bands have no Songs metadata (above).

Agent decision (#340, 2026-10-07): the owner asked that on Duo unfolded, iPad and Mac, when a profile is selected, "player/band data should take right side of the screen with nice graphs/chips/cards for each instrument". The decision is to split **each wide row**: song on the left, the player's instrument cards on the right; the list stays full width. Owner may override with `/choose`.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent |
|---|---|---|---|
| **A. Split each wide row (chosen)** | Every scored song shows its per-instrument cards on the right half of its row. | HIG Layout: "Larger spaces may show more functionality" (should). HIG Lists and tables: "consider alternatives to over-large rows" (should), met by one-line compact cards. | Operator 2026-10-04 ([split-view](../../design/apple/split-view.md)): "screens like Songs should never be split". Reuses the Songs row card, status chips and these pills. |
| B. Songs list + selected-song pane | A list/detail split with the tapped song's scores on the right. | HIG Split views (should, regular width) | Contradicts the operator's never-split Songs verdict; Song Detail already shows one song's scores. |
| C. No change | Today's chips/one-chart row. | — | Ignores the ask. |

Why A: an explicit owner choice (Songs never splits) outranks the platform's split-view recommendation, and A keeps that while using the width. The precedence-table tie-break also favours the existing row, chips and pills over a new pane. Known debt: on the iPhone Duo inner display the halves meet at the display midpoint, but the system's 40 pt hinge band (455–495 pt) is wider than the 12 pt gap, the same as the existing two-card grid.

## Fields (source default order)

| Field | Rule |
|---|---|
| Score | Bold, tabular, right-aligned positive number; 0 = **No score** |
| Accuracy / FC | [score-accuracy](../score-accuracy/spec.md) rules; FC-only when Percentage is hidden or accuracy missing |
| Percentile | Rank/total buckets; Top 1% gold emphasis, Top 5% gold outline, others neutral; no rank/total → no pill |
| Stars | 1–5 white stars; service 6 = five **gold** stars, announced distinctly |
| Season | `S9`, inverted when equal to the current catalogue season |
| Song Intensity | Catalogue chart raw + 1 on the seven-bar [meter](../difficulty-meter/spec.md); once per card |
| Game Difficulty | Player E/M/H/X (0–3), separate from Intensity; Easy/Hard use **dark** glyphs, Medium/Expert white |
| Last Played | Web: hidden under Title, injected under Last Played sort. Native: toggle-controlled date under Title (explicit deviation until that sort ships); when shown it is the **final** pill |

- The first **renderable** field becomes the primary top-trailing value (Score hidden → Accuracy/FC). The rest wrap right-aligned by measured width; grow rather than clip at large text or narrow panes. The row stays one navigation action; art and Shop badge are separate.
- A positive score on a non-Lead chart shows and speaks that chart's name (e.g. "Drums chart").
- Web layout: 390px phone wraps six fields 3+3 under a top-right score; 820px fits one row; 298/322px hysteresis for compact top placement; hiding Score at 820 switches the page to inline mode. Long titles marquee/clip on the phone.
- Not v1 goals: CSS skew, 64px clipped wide row, editable metadata order, the web's hidden-Lead fallback (natives use the first **visible** chart to respect Settings).
- Tokens: badge text ≥4.5:1 (dark on Easy/Hard, white on Medium/Expert), fills/edges ≥3:1 via `tools.contrast_gate`; rendered pixels still need device checks.
