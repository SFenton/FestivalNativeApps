# Pages router

> **What:** one row per web route with its platform-neutral spec and per-platform notes. **Read when:** working on any screen. Open the `spec` first, then only your platform's file.

Status of record: [contracts/parity-backlog.json](../../contracts/parity-backlog.json) (`python3 tools/parity_backlog.py --list` prints every gap, epic and dependency). No route is certified on any platform. "(stub)" = not yet investigated; follow [port-page](../skills/port-page.md).

<!-- BEGIN GENERATED: check_docs.py --fix -->
| Page | Route | Guard | Apple (backlog) | Spec | Platform files |
|---|---|---|---|---|---|
| home-redirect | `/` | none | partial | [spec (stub)](home-redirect/spec.md) | — |
| songs | `/songs` | none | partial | [spec](songs/spec.md) | [ios](songs/ios.md) · [ipados](songs/ipados.md) |
| song-detail | `/songs/:songId` | none | partial | [spec](song-detail/spec.md) | [ios](song-detail/ios.md) · [ipados](song-detail/ipados.md) |
| song-band-leaderboard | `/songs/:songId/bands/:bandType` | none | absent | [spec (stub)](song-band-leaderboard/spec.md) | — |
| song-leaderboard | `/songs/:songId/:instrument` | none | partial | [spec](song-leaderboard/spec.md) | [ios](song-leaderboard/ios.md) · [ipados](song-leaderboard/ipados.md) |
| player-history | `/songs/:songId/:instrument/history` | none | absent | [spec (stub)](player-history/spec.md) | — |
| player-profile | `/player/:accountId` | none | absent | [spec (stub)](player-profile/spec.md) | — |
| rivals | `/rivals` | player | absent | [spec (stub)](rivals/spec.md) | — |
| all-rivals | `/rivals/all` | player | absent | [spec (stub)](all-rivals/spec.md) | — |
| rival-detail | `/rivals/:rivalId` | player | absent | [spec (stub)](rival-detail/spec.md) | — |
| rivalry | `/rivals/:rivalId/rivalry` | player | absent | [spec (stub)](rivalry/spec.md) | — |
| statistics | `/statistics` | selection | absent | [spec (stub)](statistics/spec.md) | — |
| suggestions | `/suggestions` | selection | absent | [spec (stub)](suggestions/spec.md) | — |
| shop | `/shop` | none | partial | [spec](shop/spec.md) | [ios](shop/ios.md) · [ipados](shop/ipados.md) |
| manual | `/manual` | feature | absent | [spec (stub)](manual/spec.md) | — |
| leaderboards | `/leaderboards` | none | placeholder | [spec (stub)](leaderboards/spec.md) | — |
| full-rankings | `/leaderboards/all` | none | absent | [spec (stub)](full-rankings/spec.md) | — |
| band-rankings | `/leaderboards/bands/:bandType` | none | absent | [spec (stub)](band-rankings/spec.md) | — |
| player-bands | `/bands/player/:accountId` | none | absent | [spec (stub)](player-bands/spec.md) | — |
| bands | `/bands` | none | absent | [spec (stub)](bands/spec.md) | — |
| band-detail | `/bands/:bandId` | none | absent | [spec (stub)](band-detail/spec.md) | — |
| compete | `/compete` | player | absent | [spec (stub)](compete/spec.md) | — |
| settings | `/settings` | none | partial | [spec](settings/spec.md) | [ios](settings/ios.md) |
| licenses | `/settings/licenses` | none | absent | [spec (stub)](licenses/spec.md) | — |
<!-- END GENERATED -->

Cross-cutting web shell pieces without their own route (global search, notices, FAB actions, quick-link rail, first-run carousels, modals) are tracked under [app-navigation](../controls/app-navigation/spec.md).
