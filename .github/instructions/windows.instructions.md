---
applyTo: "windows/**"
---

# Windows code (C#, WinUI 3, Fluent)

- **Pattern first.** Before changing UI, run `python3 tools/pattern_guard.py which <file>` and read the owning [pattern](../../.agents/patterns/README.md) docs. Extend the canonical control listed there (`Festival.App/Controls/…`, `Festival.Core/Domain/…`); `ModalMarkupTests` / `HitTargetMarkupTests` and `python3 tools/pattern_guard.py` must pass.
- Follow [design/windows.md](../../.agents/design/windows.md), [design/fluent.md](../../.agents/design/fluent.md), and the `winui-design` / `winui-code-review` skills. Dialogs go through `FestivalDialog`, never `new ContentDialog`.
- Cross-platform checks bring the **intent and the pattern rule**, not the iOS mechanism. Fluent placement wins on Windows unless the pattern doc says otherwise.
- Document with C# XML docs and `#region`. Keep the coverage gates (95% non-UX / 90% UX).
