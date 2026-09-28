# Song band leaderboard — iPhone notes

> **What:** iPhone implementation state and decisions for `/songs/:songId/bands/:bandType`. **Read when:** changing this page on iPhone. Behavior: [spec.md](spec.md) (currently a stub — this file is the source of truth for what's actually built until spec.md is promoted).

Source: `FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx`, `.../components/bands/SongBandScoreFooter.tsx`. Service: `FSTService/Api/LeaderboardEndpoints.cs:98` (`/api/leaderboard/{songId}/bands/{bandType}`) — pure, keyless `GET` (`MetaDatabase.GetSongBandLeaderboard`/`GetSongBandLeaderboardEntryForAccount`/`...ForTeam`, only `SELECT`s).

- Implemented: paginated `List` of `SongBandLeaderboardEntry` rows (rank, member names, per-member instrument icons, team score, FC badge, star count), reusing `RankingsPagerView`/`RankLoadState`. A toolbar `Menu` switches `BandType` in place (mirrors `BandRankingsScreen`'s `bandTypeMenu`) rather than re-navigating, since the web page also lets the visitor switch band size without leaving. Rows navigate to `AppRoute.band(bandId:name:bandType:teamKey:)`.
- Not implemented: the instrument-combo filter (`BandFilterPill`/`BandInstrumentFilterModal`, `?combo=`) and the "selected profile's row" pin (`selectedAccountId`/`selectedBandTeamKey` query params) — both are secondary refinements on top of the base leaderboard and are deferred rather than guessed at; the `combo` parameter is already threaded through `FestivalAPI.songBandLeaderboard` so a future picker only needs UI.
- IDs: `fst.song-band-leaderboard.band-type-menu`, `fst.song-band-leaderboard.row.<bandId-or-teamKey>:<rank>`, `fst.song-band-leaderboard.page-first/previous/page-info/next/last`.
- Tests: `BandsTests.swift` (Core) covers `SongBandLeaderboardResponse`/`SongBandLeaderboardEntry` decoding, song/band-type validation and `pageCount`'s `localEntries` fallback. No hosted-UI/XCUITest coverage yet.
