# Selected-player score metadata (`fst.songs.metadata.*`) — spec

> **What:** which selected-player fields a Songs row shows, in what order and style, and where natives deliberately differ. **Read when:** changing the icons-off / single-chart selected-player row on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/utils/songSettings.ts:66-80`, `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:95-135,423-480,482-500`, `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:43-137,215-271,393-453,508-557`, `FortniteFestivalWeb/src/pages/songs/layoutMode.ts:81-101`, `FortniteFestivalWeb/src/components/songs/metadata/AccuracyDisplay.tsx:13-45`, `FortniteFestivalWeb/src/components/songs/metadata/PercentilePill.tsx:22-63`, `FortniteFestivalWeb/src/components/songs/metadata/MiniStars.tsx:17-43`, `FortniteFestivalWeb/src/components/songs/metadata/SeasonPill.tsx:12-36`, `FortniteFestivalWeb/src/components/songs/metadata/DifficultyPill.tsx:8-38`, `FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx:15-43`, `FortniteFestivalWeb/src/components/songs/metadata/SongInfo.tsx:19-48`, `FortniteFestivalWeb/src/components/common/MarqueeText.tsx:45-139`.

## When this presentation applies

Selected-player scores are available, identity- and publication-validated, and **positive** on the first enabled / explicitly filtered chart, **and** Show Instrument Icons is off or one chart is filtered. Default icons-on "All instruments" uses [status chips](../songs-instrument-status-chips/spec.md). Missing chart, 200 empty/zero, 202, 403/error, failed publication or the Filter Invalid Scores pause keep an explicit non-scored state. No per-row GET, no selected-profile headers, no blocked reads, no raw profile bytes kept across a switch. A selected band's row shows its `/song-rows` score with the same pills (no Intensity or game difficulty; [songs-profile-panel](../../patterns/songs-profile-panel.md) R5).

## Wide rows: the profile panel

Wide shells (Apple: iPad, the iPhone Duo inner display and Mac) split a selected player's or band's scored Songs rows into song | score cards. The rules (gates, one-line fit, player and band cards, grid, surfaces, accessibility, test IDs) and the A/B/C agent decision live in the [songs-profile-panel](../../patterns/songs-profile-panel.md) pattern. This control supplies the cards' pills:
- "All instruments" and band cards show only Score, Accuracy/FC, Percentile and Stars (where enabled), in the saved order, and keep them on **one line**; when they can't, the row keeps the plain presentation above (pattern R3).
- A filtered chart's single card shows every enabled field and wraps its pills in the half, like the one-chart row.

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
