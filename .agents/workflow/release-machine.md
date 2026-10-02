# Release machine (App Store Connect pipeline)

> **What:** the native side of the autonomous release machine: CI checks, `YYMM.DD.NN` version tags, the iOS archive/upload script, the App Store Connect client, credentials, release notes and the generated What's New, safety and how to enable other platforms. **Read when:** touching `tools/release/**`, `tools/windows/{package_msix.ps1,store_assets.py}`, `.github/workflows/{apple-ci,version-bump,ios-release-build,windows-release-build,store-release,*-release}.yml`, writing release-note trailers, or diagnosing a blocked/skipped release. Contract owner: `SFenton/festival-report-tracker` `docs/design.md` §2.1, §8, §11 (change both together).

## Architecture

| Piece | Where | Role |
|---|---|---|
| Orchestrator | tracker repo, Linux host | Triages issues, merges PRs, decides when to submit; dispatches `store-release` and reads its result. It never holds store credentials or calls a store itself |
| `apple-ci` | [`apple-ci.yml`](../../.github/workflows/apple-ci.yml) | Required check on PRs and `master`, hosted `xcode-27` runner: xcodegen, release-tool tests, iOS compile, `swift test`, informational coverage + inventory |
| `version-bump` | [`version-bump.yml`](../../.github/workflows/version-bump.yml) | The only automatic entry point: on every `master` push, tags each platform whose app changed with its next `<platform>/v<YYMM.DD.NN>` and dispatches that platform's build ([versions](#versions-notes-and-whats-new)) |
| `ios-release-build` | [`ios-release-build.yml`](../../.github/workflows/ios-release-build.yml) | `workflow_dispatch` only (`version_tag`, `rebuild_reason`, `dry_run`; master ref): hosted `xcode-27` runner, `store-release` environment; checks out the tag, archives + uploads a build, then the `testflight-notes` job sets its TestFlight "What to Test" |
| Versions | `tools/release/versioning.py` | `bump`, `describe`, `latest-tag`, `whats-new`, `testflight-notes`: the tag ledger, release-note trailers and generated notes |
| Build script | `tools/release/ios_appstore_build.sh` | version tag → generated `WhatsNew.json` + notes → xcodegen → `xcodebuild archive` → `-exportArchive` (uploads) → ledger entry |
| ASC client | `tools/release/fst_release.py` | `ios status\|released-versions\|submit\|beta-notes\|record-build\|creds` (also `macos …` for ASC `MAC_OS`) |
| `windows-release-build` | [`windows-release-build.yml`](../../.github/workflows/windows-release-build.yml) | `workflow_dispatch` only (`version_tag`; master ref): hosted `windows-latest` checks out the tag, generates What's New and builds the unsigned Store MSIX as an artifact ([Windows](#windows-microsoft-store)) |
| Store client | `tools/release/fst_store.py` | `fst_release.py windows status\|submit\|record-build` dispatches here (Microsoft Store submission API) |
| `store-release` | [`store-release.yml`](../../.github/workflows/store-release.yml) | `workflow_dispatch` only (`platform`, `command` status/submit, `build`, `notes_b64`, `request_id`, `dry_run`), hosted `ubuntu-latest`, `store-release` environment (master only). Runs `tools/release/actions_job.py`, which enforces policy and uploads `store-release-result` (`result.json`) |
| Secrets tool | `tools/release/store_secrets.py` | `status`, `asc`, `ios-p12`, `msstore`: validates and uploads credentials to the `store-release` environment through `gh secret set` stdin |
| Android/macOS | `android-release.yml`, `macos-release.yml` | Disabled scaffolds (below) |

`native.yml` (hosted Windows/Android unit tests) and `contracts.yml` are unchanged; the required checks are `apple-ci` and `contracts`.

## Rule: stores are touched only from Actions

Builds, signing, TestFlight uploads and store submissions run only in GitHub-hosted Actions jobs; no mesh machine (Linux host, MacBook, Windows host) runs any build/release job, holds signing material for it, or calls a store. iOS archive, signing and upload use the hosted `xcode-27` image with the released Xcode 27.0 (27A266a) selected, because App Store Connect rejects beta Xcode/SDK builds (`BUILD_SDK_NOT_ALLOWED_FOR_APP_STORE_SUBMISSION`); Xcode 27.1 (27A9269) is still beta 1. With an iOS SDK older than 27.1, `ios_appstore_build.sh` defines `FST_IOS_SDK_BEFORE_27_1`, which compiles out the iOS 27.1 Duo hinge/reserved-region probes. CI (apple-ci) keeps Xcode 27.1. Switch the release Toolchain step to `Xcode_27.1.app` once 27.1 ships (`macos-26` tops out at Xcode 26.6). Every store status read and submission uses `store-release` on hosted `ubuntu-latest`. The only credential store is the `store-release` environment (deployment branch policy: `master` only). Public release is off:

- `actions_job.py` refuses iOS App Store review submission (`blocked:"app_store_review_disabled"`) unless the repository variable `FST_APPSTORE_REVIEW_ENABLED=true`. Approved versions wait for a manual release (`releaseType=MANUAL`) while broad release is disabled. Set the variable `FST_APPSTORE_RELEASE_TYPE=AFTER_APPROVAL` to auto-release on approval.
- Windows submissions are always Manual publish (certification only).

## Pipelines

1. PR → `apple-ci` on hosted `xcode-27` (installs xcodegen with Homebrew). Compile and unit tests never boot a simulator. Swift coverage gates and `verify_product.py --strict` do not pass yet ([coverage](../testing/apple/coverage.md)), so those steps are informational.
2. Merge to `master` → `version-bump` tags `ios/v<YYMM.DD.NN>` when iOS app files changed and dispatches `ios-release-build` (merges touching no app code build nothing). It writes the ASC key from secrets to `$RUNNER_TEMP`, imports `IOS_DIST_P12_BASE64` into a throwaway keychain (or, without it, sets `FST_ALLOW_CLOUD_SIGNING=1` so Xcode uses cloud-managed distribution signing with an **Admin** key), archives and uploads, then deletes the keychain and key. The `testflight-notes` job then waits (≤45 min) for the build in ASC and sets its TestFlight notes. Exit code 4 (`{"blocked":"missing_signing"}`) becomes a neutral "skipped" job summary, not a failure. `workflow_dispatch` has a `dry_run` input.
3. The orchestrator dispatches `store-release` with `status`, reads `result.json`, picks the latest `VALID` build newer than `released_sha` (gate-checked), then dispatches `submit` with that build and base64 notes. In Actions, `FST_RELEASE_SHA_FROM_ARTIFACTS=1` maps build numbers to commits through `fst-ios-build_<build>` marker artifacts (uploaded by `ios-release-build`, 90 days) and the MSIX artifact names.

## `fst_release.py`

| Command | Behavior |
|---|---|
| `ios status --json` | `{in_review,state,version,latest_build{version,build,sha,processing_state},released_sha,blocked}`; always the full shape (blocked ⇒ `in_review:false`, exit 4; ASC failure ⇒ `blocked:"asc_error"`, exit 5) |
| `ios released-versions --json` | `{"released":[…]}`: App Store versions that reached `READY_FOR_SALE`/`READY_FOR_DISTRIBUTION` (or later released states), newest first; the build's What's New sections |
| `ios next-version [--json]` | Legacy (pre-tag) suggestion; release builds take the version from the tag |
| `ios prune-ci-certs [--dry-run] [--keep-serial S]` | Revokes development certificates named "Created via API", except `--keep-serial` (the persistent CI identity), so the account never hits Apple's certificate limit; personal Xcode certificates and all distribution certificates are kept. `ios-release-build` runs it before and after each cloud-signed archive, from the workflow commit, and continues on error |
| `ios create-certificate --csr-file F --out C [--type DEVELOPMENT]` | Creates a certificate from a CSR and writes the public DER certificate; the private key never leaves whoever made the CSR. Run by `ios-signing-cert.yml` |
| `ios beta-notes --build N (--notes-file F\|--notes-stdin) [--wait S]` | Sets the build's en-US TestFlight "What to Test" (≤4000), waiting up to `S` seconds for the build to appear |
| `ios submit --build N (--notes-file F\|--notes-stdin) [--whats-new-baseline V\|none] [--dry-run]` | Refuses (exit 3) when any version or review submission is in review. After an App Review rejection it resubmits the still-open `UNRESOLVED_ISSUES` submission that owns the version instead of creating a new one (which fails with `ITEM_PART_OF_ANOTHER_SUBMISSION`); or with `refused:"stale_whats_new"` when a version newer than the baseline has been released since the build was made; requires a `VALID`, unexpired build; creates/reuses the editable version, sets en-US What's New, attaches the build, sets `releaseType` from `FST_APPSTORE_RELEASE_TYPE` (default `MANUAL`), creates/reuses a review submission, adds the item, `submitted=true`. `--dry-run` performs GETs only and prints the planned writes |
| `ios record-build --build N --version V --sha S` | Writes `~/.local/state/fst-release/builds.json` (`FST_RELEASE_LEDGER` overrides) |
| `ios creds` | Prints key id/issuer/key path (never key material); exit 4 when missing |

In review means version state `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_APPLE_RELEASE`, `PENDING_DEVELOPER_RELEASE` (plus `PROCESSING_FOR_APP_STORE`/`PROCESSING_FOR_DISTRIBUTION`, fail-closed) or a review submission in `WAITING_FOR_REVIEW`/`IN_REVIEW`. `UNRESOLVED_ISSUES` is not in review. Never touch an in-review version: all write paths stop first.

## Credentials (never committed)

| Need | Detail |
|---|---|
| ASC API key | Team key with the **Admin** role (cloud-managed signing needs Admin; App Manager suffices only with the p12 below). `store-release` environment secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (the `.p8` text): `store_secrets.py asc --key-id … --issuer-id … --p8 AuthKey_….p8`. The workflows write it to `$RUNNER_TEMP` and export `ASC_KEY_PATH`. `fst_release.py` also reads `~/.config/fst-release/asc.json` for read-only diagnostics; `*.p8` is git-ignored |
| Apple Distribution identity (optional) | `IOS_DIST_P12_BASE64` + `IOS_DIST_P12_PASSWORD`: `store_secrets.py ios-p12 --p12 dist.p12 --password-file pw` (checks the `.p12` holds exactly one Apple Distribution certificate). Export it from Keychain Access on the Mac's GUI session (macOS refuses private-key export over SSH: "User interaction is not allowed"), copy it to the Linux host, upload, then delete both copies. Without it the job uses cloud-managed signing. The build script reads `FST_SIGNING_KEYCHAIN` + `FST_SIGNING_KEYCHAIN_PASSWORD_FILE`, set by the workflow |
| App record | Create the app once by hand in App Store Connect with bundle id `com.sfenton.festivalscoretracker.native`; until then status reports `blocked:"app_not_found"` |
| Team | `3Q9X8JX23S` is passed on the `xcodebuild` command line and in `ExportOptions-appstore.plist`, never in `project.yml` |

Check what is configured with `python3 tools/release/store_secrets.py status` (names only; values are never readable back). Missing credentials never fail the build job: status/submit report `missing_asc_credentials`, the build script reports `missing_signing`.

**One CI signing identity.** Automatic signing on a fresh hosted runner otherwise asks App Store Connect for a new Apple Development certificate on every build. The prune steps then revoke it, and Apple emails each revocation, attributed to "null null" (the API key). Instead, one persistent development identity lives in `store-release` as `IOS_DEV_P12_BASE64`/`IOS_DEV_P12_PASSWORD`. `ios-release-build` imports it into the throwaway keychain and passes its serial to `prune-ci-certs --keep-serial`; the step fails if the serial can't be read. Setting it up or rotating it, on a trusted host:
1. Generate an RSA key and CSR locally.
2. Dispatch `ios-signing-cert.yml` with `csr_b64`.
3. Download the `ios-signing-cert` artifact.
4. Build a `.p12` with legacy 3DES/SHA1 encryption (`openssl pkcs12 -export -legacy`), which macOS `security import` reads.
5. Upload it with `store_secrets.py ios-dev-p12`, then delete the key and `.p12` locally.

The certificate expires after a year; repeat this to rotate.

## Versions, notes and What's New

**Versions.** Every platform uses `YYMM.DD.NN` (operator, 2026-10-01): the UTC date of the bump plus a per-platform counter that restarts each day (`2610.01.01`, `2610.01.02`, … `2610.02.01`; at most 99 a day, and a clock behind the newest tag keeps counting on that tag's day so versions never go backwards). The ledger is annotated git tags `<platform>/v<YYMM.DD.NN>` (`ios`, `macos`, `android`, `windows`) on master commits, so no bot commits land on master. The first version is `2610.01.01`; the earlier two-part tags `ios/v2610.01`/`windows/v2610.01` were removed (iOS build 14 `2610.01` stays on TestFlight but is never submitted).

- `version-bump.yml` (every master push; serialized, never cancelled) runs `versioning.py bump --head $GITHUB_SHA --push --dispatch`. A platform bumps when files under its app paths changed since its previous tag (`*.md`, `*/WhatsNew.json`, tests and reports are excluded; see `PLATFORMS` in `versioning.py`), and android/macos only while `FST_RELEASE_<ANDROID|MACOS>_ENABLED=true`. A late run for a commit older than the newest tag is skipped (`behind_previous_tag`). If dispatching the build fails, the new tag is deleted so the next push retries. Manual: dispatch with `platform` and `force`.
- Only a version tag starts a build. Build workflows are `workflow_dispatch`-only and reject anything but `^<platform>/v[0-9]{4}\.[0-9]{2}\.[0-9]{2}$`; they run on the master ref (the environment is master-only) and check out the tag. Tag pushes by `GITHUB_TOKEN` trigger nothing, which is why the bump dispatches explicitly.
- Store numbers: iOS/macOS `CFBundleShortVersionString=YYMM.DD.NN` (three integers; ASC compares `2610.01.01` as 2610.1.1), build = `$GITHUB_RUN_NUMBER`. Android `versionName=YYMM.DD.NN`, `versionCode = YYMM*100000 + DD*1000 + NN*10 + rebuild` (rebuild 0–9; `2610.01.01` → `261001010`; `-PfstVersionName/-PfstVersionCode`). MSIX `YYMM.<DD*100+NN>.<run>.0` (e.g. `2610.101.57.0`; four 16-bit parts) with the display version stamped as `InformationalVersion` (`package_msix.ps1 -DisplayVersion`, read by `AppVersionInfo.Display`); the tracker maps MSIX versions back to `YYMM.DD.NN` for released tags. `versioning.py describe --tag T [--build N]` prints them.
- Git SHA: `FST_GIT_SHA` → Info.plist `FSTGitSHA`; iPhone Settings → App Version appends its first 7 characters. ASC cannot return Info.plist values, so `store-release` maps builds to commits through the `fst-ios-build_<build>` marker artifact (90 days). Android reads `-PfstGitSha=<sha>` or `FST_GIT_SHA` into `BuildConfig.GIT_SHA` (default `dev`, no suffix), so the release AAB build must pass the tag's commit. Windows stamps `AssemblyMetadata("FstGitSha")` from SourceLink's `SourceRevisionId` (or `-p:FstGitSha=`) on every build, including the Store MSIX whose `InformationalVersion` carries no commit. Both append the same ` · <sha7>` to Settings → App Version (issue #43).

**Release-note trailers.** Notes come from commit-message trailers on the merged commits (merge commits and the commits they bring in): `Release-Note: <text>` applies to every platform whose app the change touched; `Release-Note-iOS|macOS|Android|Windows: <text>` applies to that platform only (even without app-file changes) and replaces the generic note there; `none`/`skip`/`-` suppresses. Notes may start with a page category from `versioning.CATEGORIES` ("Songs: Rows load faster."); notes without one are classified by `CATEGORY_RULES`. TestFlight notes, store text and What's New list them grouped by category in that order, with uncategorized notes last. Notes are always specific: there is no generic fallback such as "Bug fixes and improvements." The required `inventory` check (`versioning.py check-notes`) fails a PR that touches any platform's app paths without a `Release-Note…:` trailer in its description or commits (`none` is fine when users see nothing). Each check-in (merged pull request) is one entry: its notes, or, without a trailer, its cleaned PR title (no `[Bug]` prefix or `(#n)` suffix). Commits pushed straight to master without a trailer contribute nothing, so individual code commits never become bullets. The tracker writes these from worker `release_note`/`platform_notes` into the PR description and copies them into the merge commit. Never hand-edit `WhatsNew.json` for content.

**TestFlight notes** (`versioning.py testflight-notes --released …`) are What's New for testers. They start with "Festival Score Tracker iOS YYMM.DD.NN (build N)", plus one line for a rebuild of the same tag (`rebuild_reason`: only the build number changed). Then comes **Changes since release `<v>`** (or **Changes so far (no release yet)**): every user-facing note in this build that the newest released version lacks, under page-category headings in `CATEGORIES` order with uncategorized notes under "Other". Bullets drop the category prefix. Notes come only from this platform's `Release-Note` text or untrailered PR titles, never commit subjects. A build with nothing new still repeats the full list. Past the 4000-character limit, the list ends with "…and N more." Notes without a prefix get a category from the ordered keyword rules in `versioning.CATEGORY_RULES`: the note's first four words are tried first, then the whole note. An explicit prefix always wins. Duplicate notes that differ only in case, quotes or spacing appear once. `WhatsNew.json` carries the same grouping as `groups: [{category, items}]` on every entry and on the `testflight` block, so apps don't need to re-classify.

The build script passes the same ASC released versions it uses for What's New. App Store Connect rejects some symbols in What's New and TestFlight text (e.g. `✕`: `INVALID_TEXT … contains invalid characters`), so `fst_release.asc_text` substitutes or drops them before every write (`✕`→`×`, `✓`→`check`, arrows→`->`). To re-set notes on builds already uploaded, dispatch `ios-beta-notes.yml` with `builds=58,59`. It finds each build's tag from its marker artifact and regenerates the notes with the current tools.

**In-app What's New and store text** (`versioning.py whats-new`): one `Version YYMM.DD.NN` section per *released* version plus the version being built, each holding only that platform's notes for the commits between the previous released version and it — TestFlight-only intermediate versions fold into the next released one. iOS reads released versions from ASC (`fst_release.py ios released-versions`); Windows/Android read `<platform>/released/<v>` tags, which the tracker creates when it observes a release. The build writes `WhatsNew.json` (`apple/Apps/iOS`, `apple/Apps/macOS`, `android/app/src/main/resources`, `windows/Festival.Core`, embedded) and the store "What's New" text (the newest section). The unreleased built version's entry also carries `testflight: {since, new, release, vs_release, groups}`. `groups` is the TestFlight notes' categorized `vs_release` list. Apple apps show those as "New Since …" / "In This Build vs. Release …" sections **only to TestFlight and development installs**, detected with `AppDistribution` (StoreKit `AppTransaction.environment`: sandbox = TestFlight; Debug builds skip StoreKit and honor `FST_DEBUG_DISTRIBUTION=appstore|testflight|development`). App Store installs see the single `Version …` section, and the show-once hash follows the release sections only. Android and Windows (issue #80) show the block's `groups` as one "Changes Since Release …" list to installs that did not come from the store: Android when the installer package is not `com.android.vending` (sideloads, emulator and internal builds), Windows when `Package.Current.SignatureKind` is not `Store` (sideloaded MSIX and unpackaged dev builds). Play testing tracks and Store flights install the store package and cannot be told apart at run time, so those testers see the release notes in-app and beta notes in the store's tester-notes field. Every platform renders each entry's `groups` verbatim under category headings; apps never re-classify notes. A version with nothing user-facing gets no What's New section and empty store text. The store clients then refuse with `no_user_facing_changes` (`fst_release.py`/`fst_store.py submit`; the build marker's empty `store_notes` wins over the orchestrator's), and the tracker records the build as `held` rather than submitting generic text. The checked-in files are placeholders for the first version. Clients cap entries at 20, bullets at 40 and 600 characters, and never show an empty changelog ([whats-new](../controls/whats-new/spec.md)).

**Stale baseline.** The build records `whats_new_baseline` (newest released version below it) in its marker artifact. At submit, `actions_job.py` passes it as `--whats-new-baseline`; if a newer version was released in between, ASC is untouched, the result is `refused:"stale_whats_new"` and the job dispatches one rebuild of the same tag (`rebuild_reason=stale_whats_new`, a new build number) unless an `ios-release-build` run is already queued or running. The tracker records `rebuilding` and submits the rebuilt build next. iOS submissions use the marker's `store_notes`; the orchestrator's notes are the fallback for builds without a marker. A first-ever App Store version cannot carry What's New, so it is skipped (`whats_new:"skipped_first_version"`).

## Open prerequisites

- The App Store iPhone app is iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`) and portrait-locked; iPadOS and macOS ship as separate apps later. `testDuoOuterFourRotations` is skipped until rotation returns for Duo pose work.
- `AppIcon` is the opaque 1024 px PWA icon, rendered at 2× from `https://festivalscoretracker.com/?pwaIconCapture=1&pwaIconSize=512` (the web `generate-pwa-icons.mjs` route). `ITSAppUsesNonExemptEncryption` is `false` because the app uses only system HTTPS.
- Before the first review submission, App Store Connect needs the following. App Privacy has no public API; the rest is set once:
  - App Privacy ("Data Not Collected": the app has no analytics, and Tap Telemetry is DEBUG-only)
  - Screenshots (one-off uploads, never committed)
  - Description, keywords, support and privacy URLs
  - Age rating, price, review contact and content-rights answers

## Windows (Microsoft Store)

Builds run for every `windows/v<YYMM.DD.NN>` tag that `version-bump` creates (hosted runner, so the Windows desktop is never used). Submission stays off until the tracker's `release.windows.enabled` is flipped; it then runs in `store-release`.

| Piece | Detail |
|---|---|
| Identity | `windows/store-identity.json` holds Partner Center → Product identity: `packageName` (Package/Identity/Name), `publisher` (`CN=…`), `publisherDisplayName`, `storeId`. Placeholders build artifacts suffixed `_placeholder` that are never submitted |
| Manifest | `windows/Festival.App/Package.appxmanifest`; only used with `-p:FstMsix=true` (the dev/test `.exe` stays unpackaged). Logos in `Assets/Store/` come from `windows/store/fst-icon-512.png` via `python3 tools/windows/store_assets.py` (`--check` in CI). Partner Center listing art (1:1 box art 1080/2160, 9:16 poster 720×1080/1440×2160, Store display images 300/150/71 px) comes from `--listing <dir>` and is not committed |
| Package | `tools/windows/package_msix.ps1 [-AllowPlaceholder] [-OutDir D] [-Version V]` stamps identity and the tag's version `YYMM.<DD*100+NN>.<run>.0` (without `-Version`: `<major>.<minor>.<git commit count>.0`), publishes unsigned (the Store signs) and writes `build.json {version, sha, placeholder, package}`. Artifact: `fst-windows-msix_<version>_<sha>[_placeholder]`, kept 30 days |
| Credentials | Entra app registration with a client secret, added in Partner Center → Account settings → User management → Microsoft Entra applications with the **Manager** role. `store-release` environment secrets `MSSTORE_TENANT_ID`, `MSSTORE_CLIENT_ID`, `MSSTORE_CLIENT_SECRET`, `MSSTORE_SELLER_ID`, `MSSTORE_APP_ID` (Store ID). Read-only local diagnostics may use `~/.config/fst-release/msstore.json` with lower-case keys (`FST_MSSTORE_CONFIG` overrides). Missing ⇒ `blocked:"missing_store_credentials"` |
| First submission | Must be completed by hand in Partner Center (age rating, listing, screenshots, the first CI MSIX); until then status is `blocked:"first_submission_required"` |

`windows status --json` returns the shared status shape. `state` is the pending submission's status (or `Published`), `version` its package version, and `latest_build.build` = `version` = the newest successful master artifact (`processing_state` `VALID`, `PLACEHOLDER_IDENTITY` or `EXPIRED`). `released_sha` comes from the ledger (`WINDOWS`), falling back to artifact names. In review means a pending submission in `CommitStarted`, `PreProcessing`, `Certification`, `PendingPublication`, `Publishing` or `Release`.

`windows submit --build V (--notes-file F|--notes-stdin) [--dry-run]`:

- Refuses (exit 3) while a submission is in review.
- Deletes a failed submission or one it created itself (`notesForCertification` starts with `[fst-release]`; no local state).
- Blocks on a draft someone else is editing (`foreign_pending_submission`).
- Requires `V` to be the latest valid artifact, and downloads it with `gh run download`.
- Clones the last published submission, marks the old packages `PendingDelete`, adds the new one, and sets every listing's release notes (≤1500 characters), the certification notes and `targetPublishMode: Manual`.
- Uploads the zip to the SAS URL, which is never printed, then commits.

The mode is always **Manual** (there is no option): certification runs, and the package waits in `PendingPublication` until someone presses *Publish now*. That state counts as in review, so a newer build waits too.

## Enabling other platforms

Set the repository variable `FST_RELEASE_<ANDROID|MACOS>_ENABLED=true` only after implementing the TODO steps in the scaffold workflow, then flip `release.<platform>.enabled` in the tracker's `config/machine.json`. Windows needs only the [prerequisites above](#windows-microsoft-store) plus that tracker flag.

| Platform | Plan |
|---|---|
| Android | Gradle Play Publisher with a Play service account secret and upload keystore; internal track first |
| Windows | Implemented (MSIX build + Store submission API); see [Windows](#windows-microsoft-store) |
| macOS | Copy `ios_appstore_build.sh` for `FestivalDesktop`; the client already supports `fst_release.py macos …` (ASC `MAC_OS`, bundle id `com.sfenton.festivalscoretracker.mac`) |

## Tests

`python3 -m unittest discover -s tools/release/tests -t .` (versions, tags, trailers, What's New and TestFlight notes in throwaway git repos; JWT/DER, credentials, status, next-version, submit sequence, the Store client, the Actions job policy and `store_secrets.py` with fakes; no network). `python3 tools/windows/store_assets.py --check` verifies the MSIX logos. Script check: `bash -n tools/release/ios_appstore_build.sh` and `tools/release/ios_appstore_build.sh --dry-run`.
