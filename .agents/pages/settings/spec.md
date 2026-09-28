# Settings (`/settings`) — spec

> **What:** platform-neutral web behavior of Settings: persisted preferences, sections, propagation and test matrix. **Read when:** adding or changing any setting on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/contexts/SettingsContext.tsx:18-75,280-305`, `src/pages/settings/SettingsPage.tsx:398-906`, `src/pages/settings/SettingsServiceProgress.tsx:115-407`. Audit ref: `SettingsPage.tsx:513-895`.

## Persistent app settings

- Instrument icons; visual row/column order; Paths default image/text; invalid-score filter + leeway (`-5%…+5%`, step `0.1%`, default `+1%`); experimental ranks; mobile-header actions; mouse-only light trails.
- Shop: hide Shop, Shop highlighting (separate).
- Nine chart visibility switches (the **last visible instrument cannot be disabled**) and eight metadata switches (all may be off).
- Hiding Shop disables effective highlighting, controls and Shop navigation while retaining the saved preference.
- Settings update Songs filters, Detail cards, Sort choices and leaderboard `leeway` queries.
- Reset restores **app settings only** — never the profile, song settings or tab-route history.

## Sections and actions

App · debug-only Diagnostics · Shop · Instruments · Metadata · Version · live Service Progress · first-run replays · Licenses · selected-profile name refresh (a POST: fixtures only) · ZIP export with a visible failure state · confirmed Reset. Service Progress polls faster while visible; do not keep background polling beside a game without measurement. Wide web layouts have a section rail; narrow uses modal/quick links.

## Native accessibility section (all platforms)

Per-app **additive** preferences — reduce motion, less transparency, more contrast, disable artwork animation — default to system behavior when off and can only make the app more accessible. Never promise to switch VoiceOver/TalkBack/Narrator. Every toggle announces name, on/off and any disabled reason, with keyboard focus and explicit grouping; reading order follows visible section order.

## Test matrix

Persistence/relaunch; one instrument left; all metadata off; show/hide Shop with retained highlight value; leeway limits/step/query effects; Paths default and columns; debug-only vs release controls; Service Progress loading/updating/stopped/error; first-run replay; export error; cancelled vs confirmed app-only Reset; system × in-app accessibility interactions.
