# Release machine (App Store Connect pipeline)

> **What:** the native side of the autonomous release machine: CI checks, the iOS archive/upload script, the App Store Connect client, credentials, version/build numbers, What's New, safety and how to enable other platforms. **Read when:** touching `tools/release/**`, `tools/windows/{package_msix.ps1,store_assets.py}`, `.github/workflows/{apple-ci,ios-release-build,windows-release-build,*-release}.yml`, or diagnosing a blocked/skipped release. Contract owner: `SFenton/festival-report-tracker` `docs/design.md` §2.1, §8, §11 (change both together).

## Architecture

| Piece | Where | Role |
|---|---|---|
| Orchestrator | tracker repo, Linux host | Triages issues, merges PRs, decides when to submit; calls the Mac over SSH |
| JIT runner controller | tracker repo (`fstmachine/controller.py`) | Mints a one-job self-hosted runner labelled `fst-apple-<run_id>-<attempt>` for queued jobs |
| `apple-ci` | [`apple-ci.yml`](../../.github/workflows/apple-ci.yml) | Required check on PRs and `master`: xcodegen, release-tool tests, iOS compile, `swift test`, informational coverage + inventory |
| `ios-release-build` | [`ios-release-build.yml`](../../.github/workflows/ios-release-build.yml) | On `master` pushes touching `apple/**`, `tools/release/**`, `contracts/**`: archive + upload a build |
| Build script | `tools/release/ios_appstore_build.sh` | xcodegen → `xcodebuild archive` → `-exportArchive` (uploads) → ledger entry |
| ASC client | `tools/release/fst_release.py` | `ios status\|next-version\|submit\|record-build\|creds` (also `macos …` for ASC `MAC_OS`) |
| `windows-release-build` | [`windows-release-build.yml`](../../.github/workflows/windows-release-build.yml) | On `master` pushes touching `windows/**`, `contracts/**`, packaging scripts: hosted `windows-latest` builds the unsigned Store MSIX as an artifact ([Windows](#windows-microsoft-store)) |
| Store client | `tools/release/fst_store.py` | `fst_release.py windows status\|submit\|record-build` dispatches here (Microsoft Store submission API) |
| Android/macOS | `android-release.yml`, `macos-release.yml` | Disabled scaffolds (below) |

`native.yml` (hosted Windows/Android unit tests) and `contracts.yml` are unchanged; the required checks are `apple-ci` and `contracts`.

## Pipelines

1. PR → `apple-ci` on a JIT Mac runner. Compile and unit tests take `~/.fst-build.lock` (the lock `tools/ios_sim.py` and `tools/lane_integrate.sh` use) and never boot or reset a simulator. Swift coverage gates and `verify_product.py --strict` do not pass yet ([coverage](../testing/apple/coverage.md)), so those steps are informational.
2. Merge to `master` → `ios-release-build` archives and uploads. Exit code 4 (`{"blocked":"missing_signing"}`) becomes a neutral "skipped" job summary, not a failure. `workflow_dispatch` has a `dry_run` input.
3. The orchestrator polls `fst_release.py ios status --json`, picks the latest `VALID` build newer than `released_sha` (gate-checked), then runs `ios submit --build N --notes-file F`.

## `fst_release.py`

| Command | Behavior |
|---|---|
| `ios status --json` | `{in_review,state,version,latest_build{version,build,sha,processing_state},released_sha,blocked}`; always the full shape (blocked ⇒ `in_review:false`, exit 4; ASC failure ⇒ `blocked:"asc_error"`, exit 5) |
| `ios next-version [--json]` | Reuses an editable version (`PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`); no versions ⇒ project `MARKETING_VERSION`; otherwise patch-bump of the highest of project and all ASC versions |
| `ios submit --build N (--notes-file F\|--notes-stdin) [--dry-run]` | Refuses (exit 3) when any version or review submission is in review; requires a `VALID`, unexpired build; creates/reuses the editable version, sets en-US What's New, attaches the build, `releaseType=AFTER_APPROVAL`, creates/reuses a review submission, adds the item, `submitted=true`. `--dry-run` performs GETs only and prints the planned writes |
| `ios record-build --build N --version V --sha S` | Writes `~/.local/state/fst-release/builds.json` (`FST_RELEASE_LEDGER` overrides) |
| `ios creds` | Prints key id/issuer/key path (never key material); exit 4 when missing |

In review means version state `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_APPLE_RELEASE`, `PENDING_DEVELOPER_RELEASE` (plus `PROCESSING_FOR_APP_STORE`/`PROCESSING_FOR_DISTRIBUTION`, fail-closed) or a review submission in `WAITING_FOR_REVIEW`/`IN_REVIEW`. `UNRESOLVED_ISSUES` is not in review. Never touch an in-review version: all write paths stop first.

## Credentials (Mac, never committed)

| Need | Detail |
|---|---|
| ASC API key | Admin or App Manager role. Env `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` (default `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`) or `~/.config/fst-release/asc.json` `{key_id, issuer_id, key_path, app_id?}` (`FST_RELEASE_CONFIG` overrides). `*.p8` is git-ignored |
| Apple Distribution identity | In a dedicated keychain; set `FST_SIGNING_KEYCHAIN` + `FST_SIGNING_KEYCHAIN_PASSWORD_FILE` (script unlocks it and adds it to the search list). Without a local identity the script is blocked unless `FST_ALLOW_CLOUD_SIGNING=1` |
| App record | Create the app once by hand in App Store Connect with bundle id `com.sfenton.festivalscoretracker.native`; until then status reports `blocked:"app_not_found"` |
| Team | `3Q9X8JX23S` is passed on the `xcodebuild` command line and in `ExportOptions-appstore.plist`, never in `project.yml` |

Missing credentials never fail the build job: status/submit report `missing_asc_credentials`, the build script reports `missing_signing`.

## Version and build numbers

- Marketing version: `fst_release.py ios next-version` (fallback: `apple/project.yml`, currently `0.1.0`). Override with `FST_MARKETING_VERSION`.
- Build number (`CURRENT_PROJECT_VERSION`): `$BUILD_NUMBER`, else `$GITHUB_RUN_NUMBER`, else UTC `yyyymmddHHMM`. ASC requires strictly increasing build numbers per marketing version, so do not mix schemes for one version (a timestamp build followed by a run-number build is rejected).
- Git SHA: `FST_GIT_SHA` build setting → Info.plist `FSTGitSHA` (default `dev`) and the local ledger. iPhone Settings → App Version appends its first 7 characters (`0.1.0 (42) · 42edc57`); `dev` shows none. ASC cannot return Info.plist values, so `released_sha`/`latest_build.sha` come from the ledger; a build not archived on this Mac has `sha:null`.

## What's New

Canonical content is the web `changelog.ts`; `FestivalCore/Changelog.swift` mirrors it for the in-app card ([whats-new](../controls/whats-new/ios.md)). The App Store "What's New" text is separate: the orchestrator builds it from tracker issues' `platform_notes`/`release_note` (≤4000 chars, fallback "Bug fixes and improvements.") and passes it to `ios submit`. A first-ever App Store version cannot carry What's New, so it is skipped (`whats_new:"skipped_first_version"`).

## Open prerequisites

- TODO(orchestrator): the iOS AppIcon asset is still pending (`ASSETCATALOG_COMPILER_APPICON_NAME: ""`), which App Store validation rejects; the app also needs an export-compliance answer (`ITSAppUsesNonExemptEncryption`) and a privacy/metadata record before the first submission.
- Archiving signs for device family 1 (iPhone) only (`TARGETED_DEVICE_FAMILY=1`) until iPadOS is certified.

## Windows (Microsoft Store)

Builds run on every qualifying `master` push. Submission stays off until the tracker's `release.windows.enabled` is flipped (host `linux`: `fst_store.py` and `gh` run there, so the Windows desktop is never used).

| Piece | Detail |
|---|---|
| Identity | `windows/store-identity.json` holds Partner Center → Product identity: `packageName` (Package/Identity/Name), `publisher` (`CN=…`), `publisherDisplayName`, `storeId`. Placeholders build artifacts suffixed `_placeholder` that are never submitted |
| Manifest | `windows/Festival.App/Package.appxmanifest`; only used with `-p:FstMsix=true` (the dev/test `.exe` stays unpackaged). Logos in `Assets/Store/` come from `windows/store/fst-icon-512.png` via `python3 tools/windows/store_assets.py` (`--check` in CI) |
| Package | `tools/windows/package_msix.ps1 [-AllowPlaceholder] [-OutDir D] [-Version V]` stamps identity and version `<major>.<minor>.<git commit count>.0`, publishes unsigned (the Store signs) and writes `build.json {version, sha, placeholder, package}`. Artifact: `fst-windows-msix_<version>_<sha>[_placeholder]`, kept 30 days |
| Credentials (Linux) | Entra app registration with a client secret, added in Partner Center → Account settings → User management → Microsoft Entra applications with the **Manager** role. `MSSTORE_TENANT_ID`, `MSSTORE_CLIENT_ID`, `MSSTORE_CLIENT_SECRET`, `MSSTORE_SELLER_ID`, `MSSTORE_APP_ID` (Store ID) or `~/.config/fst-release/msstore.json` with the lower-case keys (`FST_MSSTORE_CONFIG` overrides); missing ⇒ `blocked:"missing_store_credentials"` |
| First submission | Must be completed by hand in Partner Center (age rating, listing, screenshots, the first CI MSIX); until then status is `blocked:"first_submission_required"` |

`windows status --json` returns the shared status shape. `state` is the pending submission's status (or `Published`), `version` its package version, and `latest_build.build` = `version` = the newest successful master artifact (`processing_state` `VALID`, `PLACEHOLDER_IDENTITY` or `EXPIRED`). `released_sha` comes from the ledger (`WINDOWS`), falling back to artifact names. In review means a pending submission in `CommitStarted`, `PreProcessing`, `Certification`, `PendingPublication`, `Publishing` or `Release`.

`windows submit --build V (--notes-file F|--notes-stdin) [--dry-run] [--publish-mode manual|immediate]`:

- Refuses (exit 3) while a submission is in review.
- Deletes a failed submission or one it created itself (`msstore-submissions.json` beside the ledger).
- Blocks on a draft someone else is editing (`foreign_pending_submission`).
- Requires `V` to be the latest valid artifact, and downloads it with `gh run download`.
- Clones the last published submission, marks the old packages `PendingDelete`, adds the new one, and sets every listing's release notes (≤1500 characters) and `targetPublishMode`.
- Uploads the zip to the SAS URL, which is never printed, then commits.

The default mode is **Manual**: certification runs, and the package waits in `PendingPublication` until someone presses *Publish now*. That state counts as in review, so a newer build waits too.

## Enabling other platforms

Set the repository variable `FST_RELEASE_<ANDROID|MACOS>_ENABLED=true` only after implementing the TODO steps in the scaffold workflow, then flip `release.<platform>.enabled` in the tracker's `config/machine.json`. Windows needs only the [prerequisites above](#windows-microsoft-store) plus that tracker flag.

| Platform | Plan |
|---|---|
| Android | Gradle Play Publisher with a Play service account secret and upload keystore; internal track first |
| Windows | Implemented (MSIX build + Store submission API); see [Windows](#windows-microsoft-store) |
| macOS | Copy `ios_appstore_build.sh` for `FestivalDesktop`; the client already supports `fst_release.py macos …` (ASC `MAC_OS`, bundle id `com.sfenton.festivalscoretracker.mac`) |

## Tests

`python3 -m unittest discover -s tools/release/tests -t .` (JWT/DER, credentials, status, next-version, submit sequence and the Store client with fake transports; no network). `python3 tools/windows/store_assets.py --check` verifies the MSIX logos. Script check: `bash -n tools/release/ios_appstore_build.sh` and `tools/release/ios_appstore_build.sh --dry-run`.
