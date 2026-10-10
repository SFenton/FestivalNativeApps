# Band member lines

> **What:** how a band card lists its members: one line per member, the name leading on one shared edge, the member's value and instrument icons trailing, and a card-wide stack when any member can't fit. Used by Search band results, Player Bands, Profile Bands and song band boards and previews. **Read when:** you draw a band's members on a card or a leaderboard row, or change the band card.

Status: **current**, 2026-10-10. Provenance: #589 (split from #573).

## Intent

A band card's member names line up on one edge from row to row and card to card, so a list of bands scans as a neat column of names. A member's instrument count or name length never shifts where the names start (owner, #589: "usernames should align vertically for neatness").

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/player/components/PlayerBandCard.tsx` (`BandMemberRow`) | One member per line: the name leads (`flex: 1`, ellipsis), then optional metadata (a member's song score), then the instrument icons trailing (`justifyContent: flex-end`). |
| `FortniteFestivalWeb/src/pages/player/components/PlayerBandCard.tsx` (`resolveBandCardMemberLayouts`) | The card is inline or stacked as a whole: if any member's name (clamped to `MIN_MEMBER_NAME_INLINE_WIDTH` 96 … `MAX_MEMBER_NAME_INLINE_WIDTH` 180) plus its metadata and icons can't fit, **every** member stacks its icons under its name. `BAND_MEMBER_INLINE_GAP` is `Gap.md` (8). |

The web search modal renders band results with the same `PlayerBandCard`.

## Rules

1. **R1. Names lead and share one edge.** Each member gets its own line with its name first. Every name in a card, and across the cards of a list, starts on the same edge. A member's value (song score) and instrument icons follow the name, right-aligned on an inline line. The icons never come before the name.
2. **R2. Inline or stacked for the whole card.** A card draws all its lines inline (name, then value and icons) only when every member fits: the name's one-line width clamped to 96…180, plus 8 before the value and 8 before the icons. Otherwise, and always at large text, every line stacks: the name on its own line, then its value and icons wrapping under it from the same leading edge. A card never mixes inline and stacked lines.
3. **R3. Long names stay in their column.** On an inline line the name takes the space left by the trailing icons and scrolls (marquee), truncates under Reduce Motion, or wraps at large text. It never pushes the icons out of line or moves the leading edge.
4. **R4. One screen-reader stop per card.** The member lines are decorative inside the card's single accessible element: Search and Player Bands cards read "Members, Size, N appearances", Profile Bands group rows (Android, Windows; owner #596) "Members, N appearances", and song band rows read their own band announcement. Members are never separate TalkBack, VoiceOver or Narrator stops, and instrument icons are not read on their own.
5. **R5. Not this pattern.** Band Rankings rows show the joined member label ("A + B") in the leaderboard name column ([leaderboard-row](leaderboard-row.md)), with no per-member lines. Band Detail's member cards (one card per member with its own stats) have their own layout, already name-leading.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Member lines (R1–R3) | `apple/Sources/FestivalUI/Features/Profile/PlayerBandsScreen.swift` `PlayerBandRow`; `apple/Sources/FestivalUI/Features/SongDetail/SongBandPreviewSection.swift` `SongBandPreviewRow` | `android/app/src/main/java/com/festivalscoretracker/android/ui/bands/BandComponents.kt` `BandMemberRows`; fit rule `android/app/src/main/java/com/festivalscoretracker/android/core/bands/BandLayout.kt` `BandMemberFit` | `windows/Festival.App/Controls/BandCardView.xaml.cs` `BandCardView` (name column, then icons) |
| One stop per card (R4) | the row's combined accessibility element | `PlayerBandCard` and `PlayerBandRow` (merged description, member lines cleared); `BandScoreRow` (`bandScoreAnnouncement`) | `BandCardView` (one button name, member parts `Raw`) |

Android consumers: `PlayerBandCard` (Global Search band results, Player Bands), `PlayerBandRow` (Profile Bands group cards, owner #596) and `BandScoreRow` (song band board rows and Song Detail band previews, with each member's score as the value). Test tags: `fst.band-member.<accountId>.name` and `.icons` on every line. Tests: `BandMemberFitTest` (fit rule), `PlayerBandsLayoutUiTest` and `SongBandLeaderboardLayoutUiTest` (#589 alignment, stacking, long names, 200%), and the `GlobalSearchBandMembersAccessibilityJourneyTest` device journey (alignment at 100% and 200%, one TalkBack stop per result, ATF).

### Agent decision: name-leading member lines on Android (#589)

Agent decision (#589, 2026-10-10, owner may override with `/choose`). Android drew each member as an "icons, then name" chip in a wrapping flow, so names started after a different number of icons and wrapped unevenly.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| A. Keep icon-first chips; pad the icons to the widest roster | Names line up behind a fixed-width icon gutter. | material-3 skill, List: the `start` slot is a single "leading element" before the `headline` (**should**); six icons are not one leading element | None; no platform does it. | Wide empty gutters for one-instrument members; breaks at large text. |
| **B. Name first, icons trailing; whole-card stack (chosen)** | One clean column of names; icons right-aligned; at large text, icons under each name. | material-3 skill, List: "`headline` (primary text) … `trailing-supporting-text` (trailing metadata)" and "In Compose, prefer Material3 list patterns and keep spacing, leading/trailing content, supporting text … token-driven" (**should**) | Web `PlayerBandCard` `BandMemberRow`; Apple `PlayerBandRow`/`SongBandPreviewRow`; Android Band Detail members; Windows `BandCardView`. | Matches every other surface; one-instrument and six-instrument members look the same. |

**Chose B.** The web is the product source of truth, and every other platform and Android's own Band Detail already put the name first, so this is the existing behavior made shared, not a new design.

## Known debt

None recorded.

## Guards (`tools/pattern_guard.py`)

None yet.
