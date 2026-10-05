# VoiceOver walkthroughs

> **What:** the final Apple testing phase — scripted screen-reader walkthroughs per page. **Read when:** the accessibility phase is complete for a platform.

- Confirm reading order manually against each page's spec "Accessibility order" (e.g. [songs](../../pages/songs/spec.md)); automated audits do not prove order or focus bounds.
- Known unverified: iPad VoiceOver focus rectangles (XCUITest reports some grouped headers with full-window frames), focus restoration after sheets, announced page changes in paginators.
- Automated stand-ins (not VoiceOver evidence): the iPad landscape split's tree order and selected traits (`testThreeColumnReadingOrderAndTraits`) and the Mac hosted trees (`MacAccessibilityTreeTests`), see [accessibility.md](accessibility.md). Still to walk with VoiceOver: iPad focus after choosing a list row (stays on the row, detail updates), after sheet dismissal and after a compact push; Mac everything spoken (Automation Mode not authorised).
- The app never toggles VoiceOver itself; only additive in-app accessibility overrides exist.
- Transcripts: one line per step below (pass, or what was spoken / where focus went), filed as an issue per failure with platform and step number.

## Operator walkthrough script (iPad and Mac)

Run by a person, never by an agent: agents do not toggle VoiceOver, and the Mac needs Automation Mode for anything scripted (not authorised). Use the loopback fixture service so names match: iPad `FST_API_BASE_URL=http://127.0.0.1:8765` with `FST_DEBUG_PROFILE=fixture-player-1:Fixture Player 1` (or Select Profile › Fixture Player 1); Mac: `python3 tools/mac_app.py launch --profile 'fixture-player-1:Fixture Player 1' --env FST_API_BASE_URL=http://127.0.0.1:8765` ([macOS](../../platforms/apple/macos.md)). Record one line per step: **pass**, or what was spoken / where focus went instead.

**Setup.** iPad: Settings › Accessibility › VoiceOver on, rotor items Headings, Links, Form Controls, Containers; hardware keyboard attached for the second pass (VoiceOver keys Control-Option). Mac: System Settings › Accessibility › VoiceOver (⌘F5), Keyboard › Full Keyboard Access on for the FKA pass. Start from a fresh launch on Songs with Fixture Player 1 selected.

| # | Platform | Do | Expect (announcement / focus) |
|---|---|---|---|
| 1 | iPad landscape, Mac | Launch; first swipe right (VO-Right on Mac) | Window title first ("Songs"), then the sidebar: iPad Search, Songs ("selected"), Suggestions, Statistics, Rivals, Leaderboards, Item Shop, then the footer (player name, Deselect) and Settings; Mac Songs ("selected"), Suggestions, Statistics, Rivals, Compete, Leaderboards, Item Shop, then "Profile: Fixture Player 1. Show Statistics" and "Deselect Profile" |
| 2 | both | Keep swiping into the list | Songs list rows read title, artist · year, then each instrument's status ("Lead, scored; Bass, no score …"); exactly one row says "selected" (the auto-selected song). No row reads its artwork |
| 3 | both | Rotor › Headings, flick down through the detail | First heading the song title ("Fixture Orbit, Synthetic Quartet, 2026"), then Intensity, then each chart card ("Lead, 26 entries"), band cards ("Duos, No scores recorded yet") |
| 4 | both | Rotor › Quick Links (custom rotor on Song Detail, Rivals, Rival Detail, Player, Compete, Settings) | One entry per section (Song Detail: Intensity, Score History, each chart); choosing one scrolls there and moves focus to that section's header |
| 5 | iPad three columns | Double-tap another song row (Fixture Pulse) | Focus stays on the row, which now says "selected"; the detail column updates (its first heading becomes "Fixture Pulse …"); the previous row no longer says selected |
| 6 | iPad ⅓ window (compact) | Double-tap a row | The detail pushes; focus lands on the Back button or the detail's first element, never behind the pushed page. Back (two-finger scrub) returns focus to the row |
| 7 | both | Open Sort (toolbar or View › Sort…), dismiss with Escape (Mac) / two-finger scrub (iPad) | Sheet title read first; sheet traps focus (no swipe reaches the list behind it); after dismissal focus returns to the Sort button |
| 8 | both | Open Filter, change a toggle, Cancel | Toggles read their name and on/off; Cancel restores focus to Filter; the list did not change |
| 9 | both | Song Detail › Paths… | Sheet announces its title; the instrument picker reads as a pop-up/segmented control with its value; image/text toggles read their state; the karaoke warning (if shown) is a system alert read in full |
| 10 | both | Leaderboards | Each card: heading (instrument name) then rows "#2, Fixture Player 2, 38 of 50 songs, 88,000,000"; the player's own row "Your rank, 1st. Fixture Player 1."; "View all rankings (3)" |
| 11 | both | Full Rankings › page control | Page changes are announced (page N of M); the selected-profile footer reads after the rows and before the pager |
| 12 | both | Player page (choose a ranking row) | First heading the player's name; Global Statistics heading, stat tiles read label then value ("Gold Stars, 1"), instrument headings, Rank History: summary ("Latest global rank 4 of 506, total score …"), then one element per bar ("9/27/26, Rank 4 of 506, total score …"), never "0 to 1"; Audio Graph available in the rotor (Chart Details) |
| 13 | both | Rivals | Segmented "View: Song / Leaderboard"; headings Common Rivals, Lead Rivals …; rows "Fixture Rival Golf, 128 songs ahead, 243 songs behind"; one row selected in three columns |
| 14 | both | Rival Detail | Rows read both ranks ("#30 Fixture Player 1 vs #30 uwphe") and the score gap; View Profile button named |
| 15 | both | Statistics, Suggestions | Headings per section/category; Suggestions rows read title, artist · year, and the badge (Top 4%, instrument); the end text "You've seen every current suggestion." and "Start New Mix" |
| 16 | both | Item Shop | Each item reads song, artist and "Open Official Item Shop" (link on Mac); no artwork announced |
| 17 | both | Search (⌘K / sidebar Search) | Field named "Search songs or players"; the hint "Enter at least two characters" is read; results announced as they arrive (announcement), each result named |
| 18 | both | Notifications (bell / Profile › Notifications) | Sheet title; each notification reads song · instrument and its change |
| 19 | both | Settings (iPad sidebar / Mac ⌘,) | Form sections are headings; toggles read state; Licenses opens and its title is read |
| 20 | Mac | Menu bar via VO (VO-M) | Go, Song, Profile menus read every item with its shortcut; disabled items say "dimmed" |

**Keyboard (Full Keyboard Access on Mac, hardware keyboard on iPad).** Tab moves sidebar → list → detail → toolbar (Mac Tab loop; iPad Tab between focus groups, arrows inside the sidebar and list); focus rings visible on rows (`festivalRowButtonStyle`) and fields; Space/Return activates; ⌘[ goes back; Escape dismisses sheets and returns focus to the opener; ⌘F / ⌘K open search; ⇧⌘P opens profile selection. iPad: arrow keys in the sidebar move the selection and the content follows.

**Larger Text with VoiceOver (iPad, AX5).** Repeat steps 2, 3, 10 and 13: every row still reads completely (the wrapped text is one element), the sidebar footer stacks and stays reachable above the home indicator.

**Report.** File each failure as an issue with platform, step number, what was spoken and the expected text; attach a screen recording when focus moved unexpectedly.
