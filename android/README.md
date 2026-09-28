# Android foundation

Native Kotlin/Jetpack Compose single-activity preview, API 26–36. Use JDK 17,
Android SDK platform 36 and Gradle 8.14.3 (`gradle -p android` from the
repository root, or `gradle` inside `android`). The module has no checked-in
Gradle wrapper binary. Run `:app:testDebugUnitTest :app:assembleDebug
:app:assembleRelease :app:compileDebugAndroidTestKotlin`; do **not** run
`connectedAndroidTest` before the one-emulator-per-host slot is coordinated.

Compact windows use a system-inset-aware bottom bar and one pane; medium windows
use a navigation rail; expanded windows use a permanent drawer and Songs
list/detail. WindowManager observes separating folds, but real hinge spans,
continuity, text scaling, contrast and accessibility traversal are not yet
validated on devices. Android back clears detail, then returns from Settings.
The seven-bar difficulty meter is a native Canvas control. Content colors are
semantic dark tokens; additional contrast is a session-only accommodation.

## Data boundary

`assets/songs.json` is the **only catalog read by the app** in both variants.
Its local-only format is a JSON object containing a nonempty `publication`
string and `songs` array of distinct nonempty `id`, `title`, `artist` strings
and integer `difficulty` in 1–7. The fixture is a bundled preview, not a
public API response or a claim about the website's actual wire format. Read
has no remote side effects. A monotonic 60-second publication cache pins the
decoded value; errors are shown instead of silently returning stale data.

`TransportPolicy` validates the reserved debug origin
`http://10.0.2.2:8080/` (fixture server only) and release origin
`https://festivalscoretracker.com/`. Neither variant makes HTTP requests:
public Songs endpoints, publication headers, ETag and JSON shape require
verification before implementing a GET client. Only debug has INTERNET
permission and cleartext enabled for the emulator loopback; release has
neither. No privileged `X-API-Key`, POST, or production test is used.

Host unit tests cover decoding, cache expiry/invalidation/failure, origin
policy and geometry. Instrumented fixture-only UI tests compile but have not
run without an emulator. No actual coverage percentage, screenshot,
navigation/posture or performance measurement is claimed. See
`.agents/pages/songs.md`, `.agents/pages/settings.md` and
`.agents/controls/difficulty-meter.md`; contract statuses remain pending.
