# Android design (Compose)

> **What:** adaptive navigation, chrome and surfaces per Android form factor. **Read when:** laying out Android screens. Split into `design/android/<form-factor>.md` once a form factor has its own decisions.

- Material 3 first, Fluent 2 second ([fluent](fluent.md)); brand colors from `BrandTokens` (same values as Apple). Dark scheme only for now.
- Window-size policy (`AdaptiveLayoutPolicy`, unit-tested): width < 600 dp (and height ≥ 480) → bottom `NavigationBar`; < 1200 dp → `NavigationRail` (+ modal drawer from the rail header); ≥ 1200 dp → `PermanentNavigationDrawer` listing tabs + extras. Tabs follow `FestivalTabPolicy` (Apple/web `BottomNav`): Leaderboards+Rivals replace Compete at ≥ 600 dp.
- Tab roots: hamburger (modal drawer) leading, screen actions, then the profile avatar **rightmost** (initials when selected). Pushed screens show back instead. Drawer: Item Shop, Bands; Player Profile, Rivals, Player Bands when a player is selected; Licenses.
- List-detail: Songs shows list + detail panes at ≥ 840 dp or when a vertical **separating** hinge exists; the list pane ends at the hinge's leading edge, else 40% clamped to 320–440 dp.
- Glass cards: translucent `Surface` (`surfaceFrosted`) + 1 dp white 8% border, 12 dp corners, whole card is the tap target, no chevrons. No blur (moving backdrop). Increased contrast (OS contrast level on Android 14+ **or** the in-app toggle) → opaque surface + 2 dp white border.
- Section headers: white, bold, Title Case, `heading()` semantics.
- Backdrop: one shared artwork layer behind the shell; covers change every 5 s with a 1 s crossfade, zoom/pan animated in `graphicsLayer` (draw phase only), 0.7 black dim; still on reduced motion (animator scale 0 or in-app toggle), none on data saver, static focused cover on Song Detail.
- Sheets: `ModalBottomSheet` on the card color with Title Case headers (Sort Songs, Instrument, Find Player).
- In-app accessibility overrides follow the OS by default and can only make the app more accessible.

| Form factor | Decisions so far |
|---|---|
| Phone | Bottom bar; Songs list only, Detail pushed |
| Passport fold | Folded = phone; open inner (≥ 600 dp) = rail. TODO(orchestrator): verify with `device.py features` |
| Book fold | Unfolded ≥ 840 dp = rail + Songs list-detail; folded = phone |
| Tablet | Rail (portrait) / permanent drawer (≥ 1200 dp) + list-detail |
| Tri-fold | Natural landscape orientation and **no** half-open tabletop posture ([guide](https://developer.android.com/develop/adaptive-apps/guides/foldables/trifolds-and-landscape-foldables)); FST_TriFold reports FLAT folds only, so list-detail uses width rules |
