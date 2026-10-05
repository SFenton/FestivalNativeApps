---
applyTo: "apple/**"
---

# Apple code (SwiftUI: iOS, iPadOS, macOS, iPhone Duo)

- **Pattern first.** Before changing UI, run `python3 tools/pattern_guard.py which <file>` and read the owning [pattern](../../.agents/patterns/README.md) docs. Fix shared behavior in the canonical component listed there (`Design/`, `Common/`), never with a new feature-local mask, fade, material, card, row metric, header or modal treatment. `python3 tools/pattern_guard.py` must pass.
- **Materials** ([surface-materials](../../.agents/patterns/surface-materials.md), [liquid-glass.md](../../.agents/design/apple/liquid-glass.md)): system chrome is system glass; content cards, rows and custom controls use `festivalCard` / `festivalRowCard` / `festivalCardCapsule`; only `Design/GlassSurface.swift` calls `.glassEffect`. HIG Materials: "Don't use Liquid Glass in the content layer."
- **Chrome** ([nav-accessories.md](../../.agents/design/apple/nav-accessories.md)): page tools in the iPhone tab-bar accessory, Profile trailing in the header, Search tab, inline Filter Songs. Changing placement is an owner decision ([design-proposal](../../.agents/skills/design-proposal/SKILL.md)).
- **Every Apple UI decision** goes through the `apple-hig` skill (`scripts/hig_route.py`). Quote the clause and its strength (must, should, consider), and cite the HIG file in the page/control `*.md` note. HIG wins over Fluent.
- Shared Swift changes must keep the iPhone, iPad, Duo and macOS builds and tests green. Use `python3 tools/ios_sim.py` (serialized) and never call `simctl` directly. Pin `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command.
- Document with DocC `///` and `// MARK: -`. Test behavior shifts (unit plus hosted snapshot or journey), not only compilation.
