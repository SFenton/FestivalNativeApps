# Apple build and run

> **What:** commands and environment for building and launching the Apple apps. **Read when:** you need to build, launch against live/fixture data, or hit a launch-geometry problem.

## Environment

- Pin Xcode per command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (never change the global developer dir). Observed 2026-09-24: Xcode 27.1 (27A9269).
- Package: `swift build --build-tests --package-path apple`; tests `swift test --package-path apple --filter <name>` (run only new/changed tests while iterating).
- App: `python3 tools/ios_sim.py build` (Debug, this worktree); screenshots via `shot` ([lanes](../../workflow/lanes.md)).

## Service origin

| Launch | Origin |
|---|---|
| Debug and Release (default) | Keyless public `https://festivalscoretracker.com` |
| Debug + `FST_API_BASE_URL=http://127.0.0.1:8765` | Loopback [mock service](../../testing/fixtures.md) (`python3 tools/mock_service.py --port 8765`); Release ignores the override; fixture scenarios cannot target public HTTPS |
| Live contract probe | `bash tools/apple_live_service_smoke.sh --read-public-live` — see [service safety](../service-safety.md) |

Debug-only launch overrides (fixture tests only, never simulator resets): `FST_UI_TEST_CLEAR_PROFILE=1` (selected identity and notification seen-state), `FST_UI_TEST_RESET_SONG_CARDS=1` (icon/chart/metadata prefs), `FST_UI_TEST_RESET_PATH_WARNING=1` (Karaoke warning), `FST_FIXTURE_SCENARIO=…`, `FST_DEBUG_TAB` / `FST_DEBUG_ROUTE` (deep link).

## Launch screen prerequisite

Keep the `UILaunchScreen` Info.plist key and named launch colour asset. Without them iOS runs the app in a legacy 320×480 / 768×1024 compatibility frame (iPhone captured 960×1440 of 1206×2622; iPad 1536×2048 of 1668×2420), which invalidates layout and audit evidence ([TN3208](https://developer.apple.com/documentation/technotes/tn3208-preparing-your-apps-launch-screen-to-meet-app-store-requirements) also requires the key for iOS 27 SDK uploads). XCTest's `UIScreen.main` may still report runner geometry: compare **app screenshot pixels** with `SIMULATOR_MAINSCREEN_WIDTH/HEIGHT`. The iOS AppIcon asset is still pending (XcodeGen sets an empty name); distribution branding needs a separate review.

## Physical iPhone (operator device)

The project keeps `CODE_SIGNING_ALLOWED: NO` for simulator lanes; signing is supplied on the command line only for operator device installs (operator approved, 2026-09-28; team `3Q9X8JX23S`, device "iPhone 18 Pro" `00008160-00022D8230914036` registered in the portal):

```bash
cd apple && xcodegen generate -q && cd ..
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apple/FestivalNativeApple.xcodeproj -scheme FestivalMobile -configuration Release -destination "id=00008160-00022D8230914036" -derivedDataPath <scratch>/device-dd -allowProvisioningUpdates DEVELOPMENT_TEAM=3Q9X8JX23S CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic build
xcrun devicectl device install app --device 00008160-00022D8230914036 <scratch>/device-dd/Build/Products/Release-iphoneos/FestivalMobile.app
xcrun devicectl device process launch --device 00008160-00022D8230914036 com.sfenton.festivalscoretracker.native   # needs the phone unlocked
```

Never commit the team ID into `project.yml` or use another project's team (e.g. Home Assistant's) on this Mac.
