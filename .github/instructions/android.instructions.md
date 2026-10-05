---
applyTo: "android/**"
---

# Android code (Kotlin, Jetpack Compose, Material 3)

- **Pattern first.** Before changing UI, run `python3 tools/pattern_guard.py which <file>` and read the owning [pattern](../../.agents/patterns/README.md) docs. Extend the canonical component listed there (`ui/common/…`, `core/…`) instead of adding a parallel implementation, and keep `python3 tools/pattern_guard.py` passing.
- Follow [design/android.md](../../.agents/design/android.md) and the `material-3` skill (Compose Material3 references only). Build every modal with `ui/common/FestivalModal.kt`. Section headers are white, bold, Title Case, with `heading()` semantics.
- Cross-platform checks bring the **intent and the pattern rule** to Android, not the iOS mechanism. Where Material 3 and the iOS ADR differ, follow the pattern doc's platform column, or decide and document it with [design-decision](../../.agents/skills/design-decision/SKILL.md).
- Record evidence class honestly: emulator, Robolectric or code-only. Visual or gesture bugs need emulator evidence before closing as "not reproducible".
- Document with KDoc and `// region`. Keep the coverage gates (95% non-UX / 90% UX).
