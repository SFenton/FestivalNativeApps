# Instrument Selector — Android notes

> **What:** the Android port of the web Instrument Selector. **Read when:** adding an instrument picker on Android or changing `ui/design/InstrumentSelector.kt`. Behavior: [spec.md](spec.md).

- `ui/design/InstrumentSelector(instruments, selected, onSelect, hidden, disabled, muted, required, compact = null, deferSelection, keyboard, tag, content)`; pure rules in `core/songs/InstrumentSelection` (unit-tested: availability, toggle/required, auto-compact width `n × 64 + (n − 1) × 12` dp, wrap-around cycling that skips disabled charts, deferred preview).
- Full row: centred `FlowRow` of 64 dp circles with 48 dp icons; the selected chart's green disc scales in (300 ms, drawn in `drawBehind`, instant under Reduce Motion). Disabled 28% / muted 42% greyscale. Compact: previous / current / next with labelled arrows.
- `content` expands below while a rendered chart is selected (web collapsible children).
- Accessibility: one `selectableGroup`; each circle is a radio-style element named by the chart ("Unavailable" / "Conflicts with another choice" states).
- Used by: Songs Filter (deferred), Paths (required, Karaoke left out by the caller), Song Detail score history (required). Other lanes: Suggestions and Profile pickers.
- Test tags: `$tag.<wireId>`, `$tag.compact`, `$tag.previous`, `$tag.next`, `$tag.preview`.
