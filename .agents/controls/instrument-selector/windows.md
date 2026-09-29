# Instrument Selector — Windows notes

> **What:** the Windows port of the web `InstrumentSelector` (`FortniteFestivalWeb/src/components/common/InstrumentSelector.tsx`). **Read when:** adding an instrument picker to a Windows page, or changing `windows/Festival.App/Controls/InstrumentSelector*` / `Festival.Core/Domain/InstrumentSelector.cs`. TODO(orchestrator): add a platform-neutral `spec.md` and a `product.json` control id.

- Rules (`InstrumentSelectorState`, unit-tested): pressing a circle selects it, pressing the selected one clears it unless `Required`; `Hidden` instruments are not rendered (a hidden selection counts as none); `Disabled` render at 28% opacity and are skipped by the arrows; `Muted` (conflicting but selectable) render at 42% when not selected. The web's grayscale filter has no cheap XAML equivalent, so opacity alone carries the state.
- Layout: centred row of 64 epx circles with 12 epx gaps and 48 epx icons (web `Layout.demoInstrumentBtn`, `Gap.md`, `InstrumentSize.md`). `CompactMode.Auto` (default) switches to **previous / centre / next** when the control is narrower than `n × 64 + (n − 1) × 12`; `Always`/`Never` force a mode. With `DeferSelection`, arrows move a local preview while nothing is selected and the centre commits it.
- Selection: the green (`#2ECC71`) disc behind the icon scales 0 → 1 over 300 ms through `UIElement.ScaleTransition` (composition thread; instant when `Motion.Allowed` is false).
- `DetailContent` expands under the row only while a rendered instrument is selected (the web's `children`).
- Accessibility: each circle is a `ToggleButton` named by the instrument label (Toggle pattern = the web's `aria-pressed`); arrows are "Previous instrument" / "Next instrument". AutomationIds: `<IdPrefix>.<Solo_…>`, `<IdPrefix>.compact`, `<IdPrefix>.previous|next`.
- Consumers (web parity): Paths dialog, Suggestions filter, Song Detail score history. Songs filter and Leaderboards instrument picker belong to the Songs/Leaderboards lane.
