# Selected-player score metadata — Windows notes

> **What:** Windows metadata pills on Songs rows (icons off or one chart filtered). **Read when:** changing `SongMetadataPolicy` or `SongRowVisuals.Pill`. Rules: [spec.md](spec.md).

- Fields and order: web `DEFAULT_METADATA_ORDER` unless Settings' **Enable Visual Order** is on, then `SongRowVisualOrder`; Last Played is always last (native deviation, as on iPhone). Each field honors its Settings toggle; an FC with Percentage hidden still shows `FC`.
- Pills: Score (bold), accuracy (red→green tint at 25% alpha; FC = gold outline `98.5% FC`), percentile (Top 1% gold fill, Top 5% gold outline), stars (gold when 6), season (inverted when current), Intensity (`DifficultyMeter`), game difficulty (E/M/H/X on the difficulty pill brushes, dark text on Easy/Hard), Last Played date.
- First pill top-right; the rest wrap right-aligned under the title (all inline from 1100 epx). A non-Lead chart shows its icon first and is spoken ("Bass chart"). Zero score = `No score`.
