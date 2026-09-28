# All Rivals — Android notes

> **What:** Android state of `/rivals/all`. **Read when:** changing `AllRivalsScreen` / `AllRivalsViewModel` in `android/`. Full Rivals notes (data, scope, IDs, tests): [../rivals/android.md](../rivals/android.md).

- `AllRivalsRoute(scope)` carries a `RivalScope` token; `settings:common|combo` resolve against Settings at load (`RivalScopes.resolveList`), and an unresolvable scope shows "This rivals list could not be identified."
- Common Rivals intersects every chart's full list (charts without rivals are ignored, as their web 404 leaves no data); a leaderboard list shows "Your rank: #N · Total Score"; combos list their charts.
- Rows (above, then below) push Rival Detail with the same scope, in the adaptive grid (1–2 columns, split at a separating hinge). States: loading, shared service status (freeze countdown), empty, no player.
