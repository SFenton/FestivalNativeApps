# Difficulty meter — Android notes

> **What:** Compose implementation status. **Read when:** changing the meter on Android. Spec: [spec.md](spec.md).

- `ui/design/DesignPrimitives.kt` `DifficultyMeter` draws the seven 62×20 parallelograms on a `Canvas` from `core/format` `DifficultyMeterSpec` (vertices, raw/display mapping, accessible label all unit-tested); non-finite values render "Difficulty unavailable" (`fst.songs.difficulty-unavailable`).
- Open: pixel snapshot of the seven states.
