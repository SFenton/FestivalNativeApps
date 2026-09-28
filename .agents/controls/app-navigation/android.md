# App navigation — Android notes

> **What:** Android shell navigation implementation. **Read when:** changing tabs, rail, drawers or deep links on Android. Spec: [spec.md](spec.md); chrome decisions: [design/android.md](../../design/android.md).

- Tabs from `FestivalTabPolicy` (unit-tested port of Apple's); selected tab derived from the back stack; re-tap pops to root; per-tab history restored except Statistics; a profile change resolves Compete↔Leaderboards slots.
- `NavigationSuiteScaffoldLayout` + `NavigationSuite` with the policy's type (`ui/shell/FestivalApp.kt` `suiteType`): short bar / wide rail / permanent drawer; modal drawer from the top-bar hamburger (bar layouts) or rail header, gestures only while open. Test tags `fst.nav.bar|rail|permanent-drawer|drawer|drawer-sheet|profile|back|tab.<section>|drawer.<item>`; Compose tags double as UIAutomator resource ids (`testTagsAsResourceId` on the root).
- Shell seams for feature screens: `LocalShellActions` (`navigate`, `back`, `openProfile`, `search`, `notifications` slot), `RegisterPageFind { … }` (Ctrl+F; `ui/shell/ShellKeyboard.kt`). Activity shortcuts: Ctrl+K / Search key → global search, Ctrl+F → page find else global search.
- Predictive back: `enableOnBackInvokedCallback`, Navigation-Compose's built-in back animation, Material drawer/search/sheet back handling; no custom `BackHandler` in the shell.
- Debug deep links: `FST_DEBUG_TAB` / `FST_DEBUG_ROUTE` ([platforms/android.md](../../platforms/android.md)).
- Open: predictive-back animation audit, TalkBack traversal order, publication-change route clearing notice.
