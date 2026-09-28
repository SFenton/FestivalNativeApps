# Songs Filter — iPhone notes

> **What:** the SwiftUI Filter sheet as built, layout lessons and open work. **Read when:** changing Songs filtering on iPhone (Lane S; Wave 1 moves instrument selection into Filter). Spec: [spec.md](spec.md).

- Entry points: `apple/Sources/FestivalCore/{SongShopFilter,SongPlayerScoreFilter}.swift`, `apple/Sources/FestivalUI/Features/Songs/SongsFilterSheet.swift`. `SongShopFilter.filtered` preserves input order; `FestivalSession.shopOffersById` comes only from the validated feed; one `SongShopPublicationPolicy` decision gates Filter, Shop Sort/grouping and row badges.
- Toolbar Filter only for a selected player with available scores (also when Shop is hidden), plus anonymous Reset of retained Shop choices. Toolbar names each active choice.
- Sheet: opaque full-height system sheet; Shop section + "Player Score and FC Filters" disclosure (expanded when a saved predicate exists); pinned Cancel/Apply footer; Reset inside the Form.
- Put the chart ID on the disclosure **label**, not the whole `DisclosureGroup` (iOS 26 replaced all nested toggle IDs). The iOS title and Form are separate vertical siblings so AX5 text scrolls in a clipped viewport, not behind Liquid Glass.
- At AX5, scroll the **Form itself** until Reset is fully above the footer.
- Tests: `shopSongFiltersMatchSourceAndRejectAbsentFeed`, `shopPublicationMatchPreservesValidatedEmptyWithoutMixingGenerations`, `songsPauseShopDerivedRowsAcrossFailedPublicationRollover`, device `testSelectedShopFilterDraftApplyDiscardAndRelaunch`, `testSelectedShopFilterPausesAndRecoversAcrossShopStates`; pinned rollover fixture 8777 ([fixtures](../../testing/fixtures.md)).
- Open: season / percentile / stars / threshold / intensity / band sections; Shop WebSocket; rapid transitions; other AX5 states; saved-Shop-sort + failed-Shop audit.
