# Song score metadata — Android notes

> **What:** Android rendering of the icons-off / single-chart selected-player metadata pills. **Read when:** changing `SongMetadataPolicy`, `SongRowProjector` or `MetadataPill`. Behavior: [spec.md](spec.md).

- Chart: the filtered chart, else the first **visible** chart (`AppSettings.orderedVisibleInstruments`); a non-Lead chart shows and speaks "{chart} chart".
- Order: `songRowVisualOrder` when Enable Visual Order is on, else the web default; visibility from `visibleMetadata`; Last Played is always last. With Percentage hidden an FC still yields an **FC** pill.
- Pills: bold grouped score; accuracy tinted red→green at 25% (FC: gold outline, "98.7% FC"); percentile Top 1% gold fill, Top 5% gold outline, else neutral; 1–5 white stars in web `MiniStars` circles (service 6 = five gold with the gold ring; [star rating](../star-rating/android.md)); `S15` inverted for the current catalogue season; intensity meter (raw + 1); E/M/H/X difficulty (dark glyphs on Easy/Hard); "Last played 1 Sep 2026".
- The first pill sits top-trailing beside the title; the rest wrap right-aligned in a `FlowRow` (`fst.songs.metadata.<songId>`, per-field `fst.songs.metadata.<field>.<songId>`).
- Zero score, missing chart, loading/202/failed/paused scores and Filter Invalid Scores show explicit text instead (`fst.songs.score-state.<songId>`).
