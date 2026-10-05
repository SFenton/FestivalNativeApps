# VoiceOver walkthroughs

> **What:** the final Apple testing phase — scripted screen-reader walkthroughs per page. **Read when:** the accessibility phase is complete for a platform.

- Confirm reading order manually against each page's spec "Accessibility order" (e.g. [songs](../../pages/songs/spec.md)); automated audits do not prove order or focus bounds.
- Known unverified: iPad VoiceOver focus rectangles (XCUITest reports some grouped headers with full-window frames), focus restoration after sheets, announced page changes in paginators.
- Automated stand-ins (not VoiceOver evidence): the iPad landscape split's tree order and selected traits (`testThreeColumnReadingOrderAndTraits`) and the Mac hosted trees (`MacAccessibilityTreeTests`), see [accessibility.md](accessibility.md). Still to walk with VoiceOver: iPad focus after choosing a list row (stays on the row, detail updates), after sheet dismissal and after a compact push; Mac everything spoken (Automation Mode not authorised).
- The app never toggles VoiceOver itself; only additive in-app accessibility overrides exist.
- TODO(orchestrator): define the walkthrough script format and where transcripts are stored.
