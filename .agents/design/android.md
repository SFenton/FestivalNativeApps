# Android design (Compose)

> **What:** adaptive navigation and chrome per Android form factor. **Read when:** laying out Android screens. Split into `design/android/<form-factor>.md` once a form factor has its own decisions.

- Window-size-class adaptive navigation: bar → rail → drawer; list/detail scaffolds. Use Fluent Android Compose controls only when they preserve focus, touch targets and semantics.
- In-app accessibility overrides follow the OS by default and can only make the app more accessible.

| Form factor | Decisions so far |
|---|---|
| Phone | Bottom bar; TODO(orchestrator) |
| Passport fold | Record window-size and continuity tests; TODO(orchestrator) |
| Book fold | Record window-size and continuity tests; TODO(orchestrator) |
| Tablet | Rail/drawer + list/detail; TODO(orchestrator) |
| Tri-fold | Natural landscape orientation and **no** half-open tabletop posture ([guide](https://developer.android.com/develop/adaptive-apps/guides/foldables/trifolds-and-landscape-foldables)) |
