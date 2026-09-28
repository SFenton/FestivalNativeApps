# App navigation — Android notes

> **What:** Android shell navigation implementation. **Read when:** changing tabs, rail, drawers or deep links on Android. Spec: [spec.md](spec.md); chrome decisions: [design/android.md](../../design/android.md).

- Tabs from `FestivalTabPolicy` (unit-tested port of Apple's); selected tab derived from the back stack; re-tap pops to root; per-tab history restored except Statistics; a profile change resolves Compete↔Leaderboards slots.
- Bar / rail / permanent drawer by width; modal drawer from the top-bar hamburger (phone) or rail header. Test tags `fst.nav.bar|rail|drawer|drawer-sheet|profile|back|tab.<section>|drawer.<item>`.
- Debug deep links: `FST_DEBUG_TAB` / `FST_DEBUG_ROUTE` ([platforms/android.md](../../platforms/android.md)).
- Open: predictive-back animation audit, TalkBack traversal order, publication-change route clearing notice.
