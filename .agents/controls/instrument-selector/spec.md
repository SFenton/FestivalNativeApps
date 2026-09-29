# Instrument Selector (`fst.instrument-selector.*`) — spec

> **What:** platform-neutral behaviour of the web's instrument picker. **Read when:** adding or changing an instrument picker on any platform. Platform notes: [ios](ios.md) · [android](android.md) · [windows](windows.md).

Source: `FortniteFestivalWeb/src/components/common/InstrumentSelector.tsx`; consumers include `components/common/GraphCard.tsx` and the Paths, Suggestions-filter and score-history surfaces (operator batch 6, item 6.36: port it with all modes on every platform).

- **Row of instrument circles** (visible, Settings-enabled instruments only). Pressing a circle selects it; pressing the selected one clears it unless the selector is **required**.
- **States per instrument:** hidden (not rendered; a hidden selection counts as none), disabled (dimmed, skipped by arrows), muted (conflicting but selectable; dimmed when not selected), selected (green disc behind the icon, animated in; instant under reduced motion).
- **Compact mode:** when the row does not fit, show previous / current / next; forced modes Always/Never exist. **Deferred selection:** arrows move a preview while nothing is selected and the centre commits it.
- **Detail content** expands under the row only while a rendered instrument is selected.
- **Accessibility:** each circle is a toggle named by the instrument; arrows are "Previous instrument" / "Next instrument"; test IDs `fst.instrument-selector.<Solo_…>`, `.compact`, `.previous`, `.next` (or a page-specific prefix).
- Implementations: Windows `Controls/InstrumentSelector*` + Core `InstrumentSelectorState`; Apple `Design/InstrumentSelector.swift` (Lane AP5); Android `ui/design/InstrumentSelector.kt` (FST-and-songs3).

| Web input | Value |
|---|---|
| Circle | 64 px (`Layout.demoInstrumentBtn`), 48 px icon, `Gap.md` gap, centred |
| Auto-compact | row width < `n × 64 + (n − 1) × gap` |
| Disabled / muted | greyscale, opacity 0.28 / 0.42 |
| Looks | filter: green (`statusGreen`) disc scales in; graph (`GraphCard`): unselected 0.5 opacity, selected on a solid green disc |
