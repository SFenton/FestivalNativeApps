# VoiceOver walkthroughs

> **What:** the final Apple testing phase — scripted screen-reader walkthroughs per page. **Read when:** the accessibility phase is complete for a platform.

- Confirm reading order manually against each page's spec "Accessibility order" (e.g. [songs](../../pages/songs/spec.md)); automated audits do not prove order or focus bounds.
- Known unverified: iPad VoiceOver focus rectangles (XCUITest reports some grouped headers with full-window frames), focus restoration after sheets, announced page changes in paginators.
- The app never toggles VoiceOver itself; only additive in-app accessibility overrides exist.
- TODO(orchestrator): define the walkthrough script format and where transcripts are stored.
