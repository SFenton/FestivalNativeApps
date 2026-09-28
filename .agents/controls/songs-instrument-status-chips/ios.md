# Status chips — iPhone notes

> **What:** SwiftUI chip layout, drawing and tests. **Read when:** changing selected-player chip rows on iPhone. Spec: [spec.md](spec.md).

- `SongInstrumentStatusPolicy` (`FestivalCore/SongInstrumentStatus.swift`) owns classification and mode gating. SwiftUI uses a measured balanced flow: 34pt base chips, 48pt accessibility minimum, 64pt cap — no device-width detector.
- Chips show the bundled `InstrumentIcon` at 70% of the chip's side (web: 24pt icon in a 34pt chip, ≈71%; was 56%) centered in the colored fill/stroke ring, matching web `InstrumentChip.tsx`'s look. **2026-09-28 (operator request):** the corner status mark (star/checkmark/minus/exclamation) is removed — color alone now conveys status, so `inconsistentFullCombo` moved off shared red onto its own `BrandTokens.statusAmber`/`statusAmberStroke` to stay distinguishable from `noScore`. The chip-group's combined accessibility announcement (`badges.map(\.announcement)`, from `SongInstrumentStatus.announcement`) is unaffected and remains the spoken source of truth for status. `Song.sig` (real `/api/songs` field, `"Guitar"`/`"Keyboard"`) is decoded and passed as `keyboard:` for Lead/Pro Lead, so those two chips (and the Song Detail intensity row) show the keys variant for keyboard-signature songs.
- iPhone wraps nine chips 5+4 like the web phone.
- At AccessibilityXXXL, **only in chip mode**: title/artist full width, then art/Shop cue, then chips (squeezing beside art made a row 872pt tall). Other row modes keep their layout.
- Show Instrument Icons stays available in Settings without a player; metadata toggles are saved but show only in icons-off / single-chart mode.
- Tests: four Core + two hosted SwiftUI cases (four colours, reflow at 208/390/700 pt and AX5); device journeys swipe `fst.songs.list` and require the **whole** chip-group frame above the tab. Exact chart/status XCTest labels disambiguate Drums vs Pro Drums and Lead vs Pro Lead.
- Fixture: player 2 has FC Lead + non-FC Pulse Drums with a matching mock Drums chart; Bass stays empty on purpose.
