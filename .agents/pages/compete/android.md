# Compete — Android notes

> **What:** Android state of `/compete`. **Read when:** changing `core|data|presentation|ui/compete/**` in `android/`. Rivals notes: [../rivals/android.md](../rivals/android.md).

- Phone tab (`CompeteTab`, compact width with a selected player) and pushed `CompeteRoute`. Port of web `CompetePage`: scopes from `CompeteScopes.resolve` (web `resolveSupportedRankingScopes`: per family the combo first when 2+ charts in OG band / Pro Strings, then each chart).
- Leaderboards group: per scope a Top 10 Total Score card (instrument boards reuse the Leaderboards feature's `rankings`/`playerInstrumentRanking` and `AccountRankingRow`; combo boards read `GET /api/rankings/combo?combo=&rankBy=totalscore&page=1&pageSize=10` and `/api/rankings/combo/{accountId}`), the player's own row below a divider when ranked outside the top rows, "View full leaderboards" → `FullRankingsRoute` (single charts only; no native combo board yet). Combo 404 = "No scores yet".
- Rivals group: per scope 3 above / 3 below (`rivals/{chart|hexCombo}`), See All → All Rivals and rows → Rival Detail with the scope (`song:<chart>` or `combo:<hex>`). Empty/no-player copy from web `compete.*`.
- Every read retries independently (inline status); all leaderboards failed → full-page status. Toolbar Quick Links jumps to Leaderboards / Rivals. Same adaptive grid as Rivals.
- Combo rankings handlers are pure `SELECT`s (`FSTService/Api/RankingsEndpoints.cs:528-613`, `Persistence/MetaDatabase.cs:7357-7392`), inside the allowlisted `/api/rankings/*` family. TODO(orchestrator): name them in the service-safety table.
- IDs: `fst.compete.grid`, `.jump[.leaderboards|.rivals]`, `.section.<leaderboards|rivals>`, `.leaderboard-card.<scope>`, `.rivals-card.<scope>`, `.board.see-all.<scope>`, `.rivals.see-all.<scope>`, `.rank.<scope>.<key>`, `.spotlight.<scope>`. Tests: `rivals/CompeteTest.kt` (logic + Robolectric).
