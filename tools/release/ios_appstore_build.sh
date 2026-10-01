#!/usr/bin/env bash
# Archive the iOS app (scheme FestivalMobile) and upload it to App Store Connect.
#
# Usage: tools/release/ios_appstore_build.sh [--dry-run]
#
# stdout carries one JSON document (a single line):
#   {"built":true,"version":"…","build":"…","sha":"…","version_tag":"ios/v…",
#    "whats_new_baseline":…,"store_notes":"…","testflight_notes":"…"}   success
#   {"blocked":"missing_signing"}                                      exit 4 (CI maps this to a neutral skip)
# The version comes from the `ios/v<YYMM.NN>` tag on HEAD (tools/release/versioning.py); the
# build generates apple/Apps/iOS/WhatsNew.json from the released-version history in App Store
# Connect before archiving.
# Everything else (xcodebuild output, progress) goes to stderr. --dry-run prints every
# command instead of running it. Documentation: .agents/workflow/release-machine.md.
#
# Environment (all optional):
#   BUILD_NUMBER                 build number; default $GITHUB_RUN_NUMBER, else UTC yyyymmddHHMM
#   FST_VERSION_TAG              version tag to build; default the newest ios/v* tag (must point at HEAD)
#   FST_REBUILD_REASON           set when re-building an already-built version (TestFlight notes say so)
#   FST_RELEASED_VERSIONS        comma-separated released versions; skips the App Store Connect lookup
#   FST_TEAM_ID                  default 3Q9X8JX23S (must match ExportOptions-appstore.plist)
#   FST_SIGNING_KEYCHAIN         dedicated keychain holding the Apple Distribution identity
#   FST_SIGNING_KEYCHAIN_PASSWORD_FILE  file with that keychain's password
#   FST_ALLOW_CLOUD_SIGNING=1    do not require a local Apple Distribution identity
#                                (xcodebuild may use a cloud-managed one with the ASC key)
#   FST_RELEASE_BUILD_DIR        scratch dir; default <repo>/build/release-ios
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH, ~/.config/fst-release/asc.json  see fst_release.py
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_PY="$ROOT/tools/release/fst_release.py"
EXPORT_PLIST="$ROOT/tools/release/ExportOptions-appstore.plist"
PINNED_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR="${DEVELOPER_DIR:-$PINNED_DEVELOPER_DIR}"
if [ "$DEVELOPER_DIR" != "$PINNED_DEVELOPER_DIR" ]; then
  echo "DEVELOPER_DIR must be $PINNED_DEVELOPER_DIR (got $DEVELOPER_DIR)" >&2
  exit 2
fi

TEAM_ID="${FST_TEAM_ID:-3Q9X8JX23S}"
BUILD_LOCK="$HOME/.fst-build.lock"
BUILD_DIR="${FST_RELEASE_BUILD_DIR:-$ROOT/build/release-ios}"
ARCHIVE="$BUILD_DIR/FestivalMobile.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

log() { echo "[ios_appstore_build] $*" >&2; }

blocked() {
  log "blocked: $1"
  echo '{"blocked":"missing_signing"}'
  exit 4
}

# Print the command in dry-run mode, otherwise run it with stdout redirected to stderr.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '+' >&2; printf ' %q' "$@" >&2; printf '\n' >&2
  else
    "$@" >&2
  fi
}

# Same as run, serialized on the shared compile lock used by tools/ios_sim.py (flock-compatible).
run_locked() {
  if [ -x /usr/bin/lockf ]; then
    run /usr/bin/lockf -k "$BUILD_LOCK" "$@"
  else
    log "lockf not found; running without the shared build lock"
    run "$@"
  fi
}

# region Credentials and signing identity

KEY_ID="" ; ISSUER_ID="" ; KEY_PATH=""
if CREDS_JSON="$(python3 "$RELEASE_PY" ios creds 2>/dev/null)"; then
  json_field() { printf '%s' "$CREDS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
  KEY_ID="$(json_field key_id)"
  ISSUER_ID="$(json_field issuer_id)"
  KEY_PATH="$(json_field key_path)"
elif [ "$DRY_RUN" = 1 ]; then
  log "dry-run: no ASC credentials found; using placeholders"
  KEY_ID="<ASC_KEY_ID>" ; ISSUER_ID="<ASC_ISSUER_ID>" ; KEY_PATH="<ASC_KEY_PATH>"
else
  blocked "missing ASC credentials"
fi

if [ -n "${FST_SIGNING_KEYCHAIN:-}" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: would unlock $FST_SIGNING_KEYCHAIN and add it to the user keychain search list"
  elif [ -z "${FST_SIGNING_KEYCHAIN_PASSWORD_FILE:-}" ] || [ ! -r "$FST_SIGNING_KEYCHAIN_PASSWORD_FILE" ]; then
    blocked "FST_SIGNING_KEYCHAIN set without a readable FST_SIGNING_KEYCHAIN_PASSWORD_FILE"
  else
    # `security unlock-keychain` accepts the password only as an argument.
    security unlock-keychain -p "$(cat "$FST_SIGNING_KEYCHAIN_PASSWORD_FILE")" "$FST_SIGNING_KEYCHAIN" >&2
    existing="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$FST_SIGNING_KEYCHAIN" $existing
  fi
fi

if [ "$DRY_RUN" = 0 ] && [ "${FST_ALLOW_CLOUD_SIGNING:-0}" != 1 ]; then
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Distribution"; then
    blocked "no Apple Distribution identity in the keychain search list"
  fi
fi

# endregion

# region Versions

VERSIONING_PY="$ROOT/tools/release/versioning.py"
GIT_SHA="$(git -C "$ROOT" rev-parse HEAD)"
# WhatsNew.json is regenerated below, so it does not count as a local modification.
if [ -n "$(git -C "$ROOT" status --porcelain -- . ':(exclude)apple/Apps/iOS/WhatsNew.json' 2>/dev/null)" ]; then
  log "warning: working tree is dirty; the recorded SHA $GIT_SHA may not match the build"
fi

BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-$(date -u +%Y%m%d%H%M)}}"
case "$BUILD_NUMBER" in
  ''|*[!0-9]*) echo "BUILD_NUMBER must be numeric (got '$BUILD_NUMBER')" >&2; exit 2 ;;
esac

json_get() { python3 -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print("" if v is None else v)' "$1"; }

VERSION_TAG="${FST_VERSION_TAG:-}"
if [ -z "$VERSION_TAG" ]; then
  VERSION_TAG="$(python3 "$VERSIONING_PY" --repo "$ROOT" latest-tag --platform ios | json_get tag)"
fi
if [ -z "$VERSION_TAG" ]; then
  echo "no ios/v* version tag; run .github/workflows/version-bump.yml (versioning.py bump) first" >&2
  exit 2
fi
DESCRIBE="$(python3 "$VERSIONING_PY" --repo "$ROOT" describe --tag "$VERSION_TAG" --build "$BUILD_NUMBER")" || {
  echo "cannot describe $VERSION_TAG: $DESCRIBE" >&2; exit 2; }
MARKETING_VERSION="$(printf '%s' "$DESCRIBE" | json_get version)"
TAG_SHA="$(printf '%s' "$DESCRIBE" | json_get sha)"
if [ "$TAG_SHA" != "$GIT_SHA" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    log "dry-run: $VERSION_TAG is $TAG_SHA but HEAD is $GIT_SHA"
  else
    echo "$VERSION_TAG points at $TAG_SHA but HEAD is $GIT_SHA; check out the tag" >&2
    exit 2
  fi
fi

# What's New lists released versions only, so the history comes from App Store Connect.
RELEASED="${FST_RELEASED_VERSIONS-unset}"
if [ "$RELEASED" = unset ]; then
  if RELEASED_JSON="$(python3 "$RELEASE_PY" ios released-versions --json 2>/dev/null)"; then
    RELEASED="$(printf '%s' "$RELEASED_JSON" | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)["released"]))')"
  elif [ "$DRY_RUN" = 1 ]; then
    log "dry-run: released versions unavailable; assuming none"
    RELEASED=""
  else
    echo "cannot read released versions from App Store Connect" >&2
    exit 1
  fi
fi

NOTES_DIR="$BUILD_DIR/notes"
WHATS_NEW_JSON="$ROOT/apple/Apps/iOS/WhatsNew.json"
if [ "$DRY_RUN" = 1 ]; then
  NOTES_DIR="$(mktemp -d)"
  WHATS_NEW_JSON="$NOTES_DIR/WhatsNew.json"
fi
mkdir -p "$NOTES_DIR"
python3 "$VERSIONING_PY" --repo "$ROOT" whats-new --tag "$VERSION_TAG" --released "$RELEASED" \
  --out "$WHATS_NEW_JSON" --store-notes-out "$NOTES_DIR/store-notes.txt" >&2
TF_ARGS=(--tag "$VERSION_TAG" --build "$BUILD_NUMBER" --out "$NOTES_DIR/testflight-notes.txt")
if [ -n "${FST_REBUILD_REASON:-}" ]; then TF_ARGS+=(--rebuild-reason "$FST_REBUILD_REASON"); fi
python3 "$VERSIONING_PY" --repo "$ROOT" testflight-notes "${TF_ARGS[@]}" >&2
log "version $MARKETING_VERSION ($VERSION_TAG) build $BUILD_NUMBER sha $GIT_SHA released [${RELEASED}]"

# endregion

# region Build

AUTH_FLAGS=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")

if [ "$DRY_RUN" = 0 ]; then
  rm -rf "$ARCHIVE" "$EXPORT_DIR"
  mkdir -p "$BUILD_DIR"
fi

(cd "$ROOT/apple" && run xcodegen generate -q)

# App Store Connect rejects beta SDKs. With a released Xcode whose iOS SDK predates 27.1,
# compile out the iOS 27.1 Duo APIs (DeviceLayoutEnvironment.swift).
SWIFT_CONDITIONS='$(inherited)'
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 0)"
if [ "$(printf '%s\n27.1\n' "$SDK_VERSION" | sort -V | head -1)" != "27.1" ]; then
  SWIFT_CONDITIONS="$SWIFT_CONDITIONS FST_IOS_SDK_BEFORE_27_1"
fi
log "iOS SDK $SDK_VERSION; Swift conditions: $SWIFT_CONDITIONS"

run_locked xcodebuild archive \
  -project "$ROOT/apple/FestivalNativeApple.xcodeproj" \
  -scheme FestivalMobile \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -allowProvisioningUpdates "${AUTH_FLAGS[@]}" \
  -quiet \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic \
  TARGETED_DEVICE_FAMILY=1 \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="$SWIFT_CONDITIONS" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  FST_GIT_SHA="$GIT_SHA"

# destination=upload in the plist makes -exportArchive upload straight to App Store Connect.
run_locked xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates "${AUTH_FLAGS[@]}"

run python3 "$RELEASE_PY" ios record-build --build "$BUILD_NUMBER" --version "$MARKETING_VERSION" --sha "$GIT_SHA"

# endregion

python3 - "$DRY_RUN" "$MARKETING_VERSION" "$BUILD_NUMBER" "$GIT_SHA" "$VERSION_TAG" "$WHATS_NEW_JSON" \
  "$NOTES_DIR" "${FST_REBUILD_REASON:-}" <<'PY'
import json, sys
from pathlib import Path
dry, version, build, sha, tag, whats_new, notes, reason = sys.argv[1:9]
doc = json.loads(Path(whats_new).read_text())
print(json.dumps({"built": True, "dry_run": dry == "1", "version": version, "build": build, "sha": sha,
                  "version_tag": tag, "whats_new_baseline": doc.get("baseline"),
                  "store_notes": (Path(notes) / "store-notes.txt").read_text().strip(),
                  "testflight_notes": (Path(notes) / "testflight-notes.txt").read_text().strip(),
                  "rebuild_reason": reason or None}, ensure_ascii=False))
PY
