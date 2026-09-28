# Controls router

> **What:** one row per contract control with its platform-neutral spec and per-platform notes. **Read when:** working on a control. Open the `spec` first, then only your platform's file.

All controls are `pending` until every platform has state/visual/accessibility evidence ([strategy](../testing/strategy.md)). Test IDs and states come from [contracts/product.json](../../contracts/product.json).

<!-- BEGIN GENERATED: check_docs.py --fix -->
| Control | Test ID | States | Status | Spec | Platform files |
|---|---|---|---|---|---|
| difficulty-meter | `fst.songs.difficulty-meter` | 8 | pending | [spec](difficulty-meter/spec.md) | [ios](difficulty-meter/ios.md) |
| artwork-background | `fst.shell.artwork-background` | 5 | pending | [spec](artwork-background/spec.md) | [ios](artwork-background/ios.md) · [windows](artwork-background/windows.md) |
| songs-sort | `fst.songs.sort` | 17 | pending | [spec](songs-sort/spec.md) | [ios](songs-sort/ios.md) · [ipados](songs-sort/ipados.md) · [windows](songs-sort/windows.md) |
| songs-filter | `fst.songs.filter` | 29 | pending | [spec](songs-filter/spec.md) | [ios](songs-filter/ios.md) · [windows](songs-filter/windows.md) |
| score-accuracy | `fst.score.accuracy.*` | 16 | pending | [spec](score-accuracy/spec.md) | [ios](score-accuracy/ios.md) · [ipados](score-accuracy/ipados.md) |
| chopt-paths | `fst.song-detail.paths` | 12 | pending | [spec](chopt-paths/spec.md) | [ios](chopt-paths/ios.md) · [ipados](chopt-paths/ipados.md) · [windows](chopt-paths/windows.md) |
| shop-offers | `fst.songs.shop` | 14 | pending | [spec](shop-offers/spec.md) | [ios](shop-offers/ios.md) · [windows](shop-offers/windows.md) |
| app-navigation | `fst.nav.*` | 6 | pending | [spec](app-navigation/spec.md) | [ios](app-navigation/ios.md) · [ipados](app-navigation/ipados.md) |
| profile-selection | `fst.profile.*` | 17 | pending | [spec](profile-selection/spec.md) | [ios](profile-selection/ios.md) · [ipados](profile-selection/ipados.md) · [windows](profile-selection/windows.md) |
| songs-instrument-status-chips | `fst.songs.instrument-status.*` | 21 | pending | [spec](songs-instrument-status-chips/spec.md) | [ios](songs-instrument-status-chips/ios.md) · [ipados](songs-instrument-status-chips/ipados.md) · [windows](songs-instrument-status-chips/windows.md) |
| song-score-metadata | `fst.songs.metadata.*` | 32 | pending | [spec](song-score-metadata/spec.md) | [ios](song-score-metadata/ios.md) · [ipados](song-score-metadata/ipados.md) · [windows](song-score-metadata/windows.md) |
| notifications | `fst.notifications.*` | 8 | pending | [spec](notifications/spec.md) | [ios](notifications/ios.md) · [windows](notifications/windows.md) |
| quick-links | `fst.quick-links.*` | 5 | pending | [spec](quick-links/spec.md) | [ios](quick-links/ios.md) · [windows](quick-links/windows.md) |
| songs-section-index | `fst.songs.section-index.*` | 5 | pending | [spec](songs-section-index/spec.md) | [ios](songs-section-index/ios.md) |
| first-run | `fst.first-run.*` | 6 | pending | [spec](first-run/spec.md) | [ios](first-run/ios.md) · [windows](first-run/windows.md) |
| service-status | `fst.service-status.*` | 8 | pending | [spec](service-status/spec.md) | [ios](service-status/ios.md) |
<!-- END GENERATED -->
