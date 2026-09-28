# Status chips — iPhone notes

> **What:** SwiftUI chip layout, drawing and tests. **Read when:** changing selected-player chip rows on iPhone (Wave 1 adds instrument icons inside the circles). Spec: [spec.md](spec.md).

- `SongInstrumentStatusPolicy` (`FestivalCore/SongInstrumentStatus.swift`) owns classification and mode gating. SwiftUI uses a measured balanced flow: 34pt base chips, 48pt accessibility minimum, 64pt cap — no device-width detector.
- Chip glyphs are **native-drawn initials/marks**, not the web PNGs (rights unresolved); Keyboard/Pro Keys `sig` variants wait for catalogue signature data and licensed icons.
- iPhone wraps nine chips 5+4 like the web phone.
- At AccessibilityXXXL, **only in chip mode**: title/artist full width, then art/Shop cue, then chips (squeezing beside art made a row 872pt tall). Other row modes keep their layout.
- Show Instrument Icons stays available in Settings without a player; metadata toggles are saved but show only in icons-off / single-chart mode.
- Tests: four Core + two hosted SwiftUI cases (four colours, reflow at 208/390/700 pt and AX5); device journeys swipe `fst.songs.list` and require the **whole** chip-group frame above the tab. Exact chart/status XCTest labels disambiguate Drums vs Pro Drums and Lead vs Pro Lead.
- Fixture: player 2 has FC Lead + non-FC Pulse Drums with a matching mock Drums chart; Bass stays empty on purpose.
