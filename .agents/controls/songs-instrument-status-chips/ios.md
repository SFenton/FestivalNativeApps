# Status chips — iPhone notes

> **What:** SwiftUI chip layout, drawing and tests. **Read when:** changing selected-player chip rows on iPhone. Spec: [spec.md](spec.md).

- `SongInstrumentStatusPolicy` (`FestivalCore/SongInstrumentStatus.swift`) owns classification and mode gating. SwiftUI uses a measured balanced flow: 34pt base chips, 48pt accessibility minimum, 64pt cap — no device-width detector.
- Chips now show the bundled `InstrumentIcon` (56% of the chip's side) centered in the colored fill/stroke ring, matching web `InstrumentChip.tsx`'s look. The former native-drawn letter abbreviation ("L", "PD", …) is gone; the non-color status mark (star/checkmark/minus/exclamation) survives as a small bottom-trailing corner badge instead of the chip's whole glyph, so color-blind/greyscale accessibility is unchanged. Keyboard/Pro Keys `sig` variants still wait for the `Song` model to expose a signature field (not added this wave — `SongCatalog.swift` is outside Lane S's owned Core files).
- iPhone wraps nine chips 5+4 like the web phone.
- At AccessibilityXXXL, **only in chip mode**: title/artist full width, then art/Shop cue, then chips (squeezing beside art made a row 872pt tall). Other row modes keep their layout.
- Show Instrument Icons stays available in Settings without a player; metadata toggles are saved but show only in icons-off / single-chart mode.
- Tests: four Core + two hosted SwiftUI cases (four colours, reflow at 208/390/700 pt and AX5); device journeys swipe `fst.songs.list` and require the **whole** chip-group frame above the tab. Exact chart/status XCTest labels disambiguate Drums vs Pro Drums and Lead vs Pro Lead.
- Fixture: player 2 has FC Lead + non-FC Pulse Drums with a matching mock Drums chart; Bass stays empty on purpose.
