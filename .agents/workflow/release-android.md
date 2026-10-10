# Android release (Google Play)

> **What:** how Android builds reach Google Play testers, its credentials and the one-time owner setup. **Read when:** changing `android-release.yml`, `play_release.py` or Android signing, or setting up Play. Shared release rules: [release-machine.md](release-machine.md).

## Pipeline

`android-release.yml` builds the App Bundle for an `android/vYYMM.DD.NN` tag (`versionCode` from `versioning.py`), signs it with the **upload key**, checks the signer, and always attaches it as the `android-release-<version>` artifact (30 days). When `FST_PLAY_PUBLISH_ENABLED` is `true` it publishes to the chosen track (default `internal`) through `tools/release/play_release.py`: Play Developer API v3 edits, an `openssl`-signed service-account token, no third-party action. Release notes come from the tag's `Release-Note` trailers, clipped to Play's 500 characters. Play App Signing holds the app signing key, so a lost upload key can be reset in Play Console with the upload certificate.

| Variable / secret (`store-release`) | Set by |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS` | `store_secrets.py android-upload-key --generate ~/.config/fst-release/android` (new PKCS#12 key, password and certificate saved mode 600 there, never printed; **back that folder up**), or `--keystore … --password-file …` |
| `PLAY_SERVICE_ACCOUNT_JSON` | `store_secrets.py play --service-account-json key.json`, then delete the downloaded key |
| Repo variable `FST_RELEASE_ANDROID_ENABLED` | `true`: `version-bump.yml` tags Android changes and dispatches `android-release.yml` |
| Repo variable `FST_PLAY_PUBLISH_ENABLED` | `true` only after the first bundle was uploaded by hand (below) |

## First release (owner, once)

Google requires the first bundle of a new app to be uploaded by hand:
1. Play Console developer account (identity verified). Personal accounts created after 2023-11-13 need a 14-day, 12-tester closed test before production; internal testing (up to 100 testers, no review) does not.
2. Create the app (package `com.festivalscoretracker.android` is fixed by the first bundle), then complete *App content* (privacy policy, data safety, ads, content rating, target audience) far enough for testing.
3. Generate and upload the upload key, set `FST_RELEASE_ANDROID_ENABLED=true`, and run `android-release.yml` (or let the next Android change bump a tag). Download the artifact.
4. Play Console > Test and release > Testing > Internal testing: create the tester list, create a release, upload the `.aab` (opt in to Play App Signing), and roll it out. Share the opt-in link with testers.
5. Google Cloud: enable the *Google Play Android Developer API* in a project, create a service account (no Cloud roles) and a JSON key. Play Console > Users and permissions: invite the service-account email with access to this app: *View app information*, *Release to testing tracks* (production later) and *Manage testing tracks*. Upload the key with `store_secrets.py play`.
6. Verify with a manual `android-release.yml` run after setting `FST_PLAY_PUBLISH_ENABLED=true`. `play_release.py` reports `app_not_ready` until the first upload exists, and `draft` while Play still treats the app as a draft app (finish the first rollout in Play Console).

After that, every Android change reaching master is tagged, built and on the internal track within minutes; testers update from the Play Store. Production, closed testing and staged rollouts are not automated yet.
