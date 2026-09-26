# Settings (`/settings`) - not yet certified

Source: `FortniteFestivalWeb/src/contexts/SettingsContext.tsx:18-75,280-305`, `src/pages/settings/SettingsPage.tsx:398-906`, `src/pages/settings/SettingsServiceProgress.tsx:115-407`.

**Persistent app settings:** instrument icons, visual row/column order, Paths default image/text, invalid-score filter/leeway (`-5%...+5%`, step `0.1%`, default `+1%`), experimental ranks, mobile-header actions, mouse-only light trails; separate Shop hide/highlighting; nine chart visibility switches and eight metadata switches. Last visible *instrument* cannot be disabled, but all metadata can be off. Hiding Shop disables effective highlighting/control/Shop navigation while retaining its saved preference. Settings update Songs filters, Detail cards, sort choices and leaderboard leeway queries. Settings reset restores **app settings only**, never profile, song settings or tab-route history.

**Sections/other actions:** App, debug-only Diagnostics, Shop, Instruments, Metadata, Version, live Service Progress, first-run replays, Licenses, selected-profile name refresh, ZIP export with a visible failure state, and confirmed Reset. Service Progress polls more frequently while visible; do not retain background polling beside a game without measurement. Profile refresh is a POST; test with fixtures, no production mutation. Export must reveal an error rather than pretend a download succeeded. Wide desktop has a section rail; narrow uses native modal/quick links.

**New native accessibility section:** per-app additive preferences for reduced motion, less transparency, more contrast and disabling artwork animation, defaulting to the system behavior when off. The Apple slice now uses Reduce Motion and Disable Animated Artwork to hold a static cover, Increase Contrast to strengthen accent/borders and increase art dimming, and Reduce Transparency to remove decorative imagery/dim layers as well as replace the solo pager's material with an opaque surface. System Low Data and Low Power Mode also disable the appropriate background work. Native `Section` headers retain their grouping semantics but explicitly use the lighter `textSecondary` token instead of system gray over the translucent artwork gaps. The pure-white synthetic fixture checks three fully visible section headings against their **actual screenshot pixels** at ≥4.5:1 and captures top/scrolled positions; Xcode's full Settings accessibility audit can still misreport a partially offscreen heading or translucent compact navigation title, and **Settings is not audit-certified**. Never turn that finding into a blanket waiver. Do not promise to switch VoiceOver/TalkBack/Narrator on or off. Every toggle must announce name, on/off and any disabled reason, with keyboard focus and explicit grouping; reader order follows visible section order rather than animations.

**Test matrix:** persistence/relaunch, one instrument left, all metadata off, show/hide Shop and retained highlight value, leeway limits/step/query effects, changed Paths defaults/columns, debug-only vs release controls, service loading/updating/stopped/error, first-run replay, export error, canceled/confirmed app-only Reset and system/in-app accessibility interactions.

**Current Apple propagation:** Instrument visibility updates Songs filtering, Detail leaderboard cards and Paths choices but leaves charted Intensity visible; a selected iPhone/iPad journey hides Bass, verifies those distinct effects and restores the switch. Invalid-score leeway reaches the solo request. CHOpt Path Default View announces its Image/Text selection and initializes the real path modal; Reset also restores the Karaoke warning preference. Hide Item Shop removes its route/action with a notice, while saved highlights change **Shop cards, Songs red/gold offer rows and the Detail badge** without hiding the valid outbound action. A selected device journey proves those controls on iPhone and iPad; a separate `shop-error` fixture keeps Songs populated and surfaces the actual Shop failure on Songs/Detail, unlike `shop-empty`. Artwork accessibility overrides and app-only Reset retain their previous selected proofs.

Checking a changed publication refetches catalogue/art paths before
reporting success; a failed Songs read is shown separately rather
than claiming the publication read failed. A successful check still
announces stale/offline or live-headerless Songs provenance. Native
UI automation checks that background pixels animate, become static
under motion overrides and return to the opaque brand surface when
transparency is reduced. **Still pending:** Shop filters and
profile/FC conditional Songs sorts, draggable path column order,
only-Karaoke-visible Paths guard, Service Progress, exports,
band profiles, first-run replay and most PWA settings. Settings
itself remains `pending` until its complete page audit and all
states have evidence.
With a selected player, all eight metadata toggles are now enabled:
seven independently change backed text on the native Songs row,
and Intensity gates its already-charted meter in a filtered row.
**Intensity also remains enabled without a selected player**:
an anonymous user who turns off the filtered Songs meter can
turn it back on without selecting another profile or resetting
the app. The other seven, player-specific metadata toggles
stay disabled anonymously with an explicit reason. A serial
**7/7 iPhone and 7/7 iPad** selected matrix includes a real
anonymous Intensity off/on meter test, selected
Score/Percentage and Hide Lead reattribution with original
switches restored. Hosted tests exercise all seven
label flags. Filter Invalid Scores **does not yet** evaluate the
source's precomputed `ml`/`vs`/`rt` fallback variants for Songs:
the selected card shows a visible pending message rather than a
raw score disguised as valid. Show Instrument Icons is now
enabled, with status descriptions: a selected, published,
unfiltered player shows enabled chart chips; turning icons
off restores the ordinary first-visible-chart score fields.
The seven other metadata switches retain their saved values
but take visible effect only with icons off or one chart
filtered. The 10/10-per-device selected matrix verifies
Show Instrument Icons and Lead visibility changes affect
the same card, then filtering Drums restores its real
Score 88,800. Experimental ranks stay disabled.
Metadata ordering, complete
Detail propagation, source filter controls, accessibility/focus
audits and live selected-player access remain pending; Settings
is not route-certified.
