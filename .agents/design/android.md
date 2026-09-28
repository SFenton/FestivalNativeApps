# Android design (Compose)

> **What:** adaptive navigation, chrome and surfaces per Android form factor. **Read when:** laying out Android screens. Split into `design/android/<form-factor>.md` once a form factor has its own decisions.

- Material 3 first, Fluent 2 second ([fluent](fluent.md)); brand colors from `BrandTokens` (same values as Apple). Dark scheme only for now.
- Window-size policy (`AdaptiveLayoutPolicy`, unit-tested) drives `NavigationSuiteScaffoldLayout` with an explicit `NavigationSuiteType` (Material 3's `navigationSuiteType` rules plus a large-window drawer): width < 600 dp → `ShortNavigationBarCompact`; compact height (< 480 dp) or **tabletop** → bottom `ShortNavigationBarMedium` (controls in the lower half); < 1200 dp → `WideNavigationRailCollapsed` (+ modal drawer from the rail header); ≥ 1200 dp → `NavigationDrawer` (permanent, 280 dp) listing tabs + extras. Bars sit below the content (not overlaid). Tabs follow `FestivalTabPolicy` (Apple/web `BottomNav`): Leaderboards+Rivals replace Compete at ≥ 600 dp.
- Top bars: hamburger (modal drawer, bar layouts only) or back leading; screen actions, **global search** (icon, or a persistent search pill on expanded windows — [global-search](../controls/global-search/android.md)), the notifications slot, then the profile avatar **rightmost** on tab roots (initials when selected). Drawer: Item Shop, Bands; Player Profile, Rivals, Player Bands when a player is selected; Licenses. The modal drawer takes gestures only while open, so edge swipes stay system (predictive) back.
- List-detail: Songs shows list + detail panes at ≥ 840 dp or when a vertical **separating** hinge exists; the list pane ends at the hinge's leading edge, else 40% clamped to 320–440 dp.
- Glass cards: translucent `Surface` (`surfaceFrosted`) + 1 dp white 8% border, 12 dp corners, whole card is the tap target, no chevrons. No blur (moving backdrop). Increased contrast (OS contrast level on Android 14+ **or** the in-app toggle) → opaque surface + 2 dp white border.
- Section headers: white, bold, Title Case, `heading()` semantics.
- Backdrop: one shared artwork layer behind the shell; covers change every 5 s with a 1 s crossfade, zoom/pan animated in `graphicsLayer` (draw phase only), 0.7 black dim; still on reduced motion (animator scale 0 or in-app toggle), none on data saver, static focused cover on Song Detail.
- Sheets: `ModalBottomSheet` on the card color with Title Case headers (Sort Songs, Instrument, Find Player).
- In-app accessibility overrides follow the OS by default and can only make the app more accessible.

| Form factor | Verified on the FST AVDs (`tools/android/search_journey.py`, screenshots `android/reports/screenshots/search-*.png`, `shell-*.png`) |
|---|---|
| Phone | Short bar; Songs list only, Detail pushed; search = full-screen view from the top-bar icon |
| Passport fold | Folded (cover) = phone. Unfolded (≈ 840 dp) = rail + Songs list-detail at the hinge; the list pane is < 400 dp so search is the icon, and its docked panel stays left of the fold |
| Book fold | Folded = phone. Unfolded / book posture = rail + list-detail at the hinge, docked search left of the fold. **Tabletop** (half-open, rotated) = docked panel capped above the fold (verified); bottom bar per policy (hidden by the IME in the capture). Search text/scope/results survive every posture change (docked ↔ full screen) |
| Tablet | Landscape = permanent drawer + list-detail, persistent search pill (or icon on a narrow pane); portrait = rail, docked search re-anchored on rotation |
| Tri-fold | Folded (360 dp) = phone; partial (720 dp) = rail + docked search; unfolded (1080 dp) = rail + list-detail. FLAT folds only (no tabletop) |
| Resizable | Presets phone → tablet → desktop switch bar → rail → permanent drawer live with search open |
