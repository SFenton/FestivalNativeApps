# Songs Sort — iPhone notes

> **What:** the SwiftUI Sort sheet as built and its layout lessons. **Read when:** changing Songs sorting on iPhone. Spec: [spec.md](spec.md).

- `SongCatalogSort` (Core) + `Features/Songs/SongsSortSheet.swift`: Title, Artist, Year, Duration, plus Item Shop only when Shop is visible (disabled until a validated feed loads). Segmented direction; in-Form Reset; fixed Cancel/Apply footer; gesture dismissal disabled. `@AppStorage` persists only the applied preference.
- Sort sits in a `ToolbarItemGroup(.topBarTrailing)` alongside Filter (a `ToolbarSpacer` separates them from the profile button on iOS 26): bottom placement overlapped the Liquid Glass tab and activated Leaderboards. The toolbar button tints gold whenever the applied mode/direction isn't default Title A-Z.
- Title/Artist/Year sorting now drives a right-edge section-index "drag to jump" scrubber over the List ([songs-section-index/ios.md](../songs-section-index/ios.md)); it has no equivalent on web.
- Web differences: six radio rows with arrow hints and a red Reset vs native five inline choices; Has FC not ported; full-height system sheet vs web bottom sheet.
- Grouped Shop sections: zero vertical List insets on headers/links, 16pt horizontal gutters, so two selected cards clear the floating tab (`testSelectedShopSortSongsRowsClearFloatingTab`).
- Visual fixtures pin Title per launch via launch arguments without touching the saved preference.
- Tests: `SongCatalogSortTests`, device `testAnonymousSongsSortDraftApplyDiscardAndRelaunch`, `testAnonymousItemShopSortRestoresAfterHideAndFeedFailure`; web cases "anonymous Sort modal" / "anonymous Item Shop sort reorders Songs" in `tools/visual/pages.spec.ts`.
- Open: Has FC and profile/band modes, metadata priorities, quick-link rail, landscape, largest type, grouped-screen full audit.
