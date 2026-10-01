#!/usr/bin/env bash
# Archive the iOS app (scheme FestivalMobile) and upload it to App Store Connect.
#
# Usage: tools/release/ios_appstore_build.sh [--dry-run]
#
# stdout carries one JSON document:
#   {"built":true,"version":"…","build":"…","sha":"…"}   success
#   {"blocked":"missing_signing"}                         exit 4 (CI maps this to a neutral skip)
# Everything else (xcodebuild output, progress) goes to stderr. --dry-run prints every
# command instead of running it. Documentation: .agents/workflow/release-machine.md.
#
# Environment (all optional):
#   BUILD_NUMBER                 build number; default $GITHUB_RUN_NUMBER, else UTC yyyymmddHHMM
#   FST_MARKETING_VERSION        skip `fst_release.py ios next-version`
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
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

GIT_SHA="$(git -C "$ROOT" rev-parse HEAD)"
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
  log "warning: working tree is dirty; the recorded SHA $GIT_SHA may not match the build"
fi

BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-$(date -u +%Y%m%d%H%M)}}"
case "$BUILD_NUMBER" in
  ''|*[!0-9]*) echo "BUILD_NUMBER must be numeric (got '$BUILD_NUMBER')" >&2; exit 2 ;;
esac

project_marketing_version() {
  sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\} *$/\1/p' "$ROOT/apple/project.yml" | head -1
}

MARKETING_VERSION="${FST_MARKETING_VERSION:-}"
if [ -z "$MARKETING_VERSION" ]; then
  if ! MARKETING_VERSION="$(python3 "$RELEASE_PY" ios next-version 2>/dev/null)" || [ -z "$MARKETING_VERSION" ]; then
    MARKETING_VERSION="$(project_marketing_version)"
    log "next-version unavailable; using project MARKETING_VERSION $MARKETING_VERSION"
  fi
fi
log "version $MARKETING_VERSION build $BUILD_NUMBER sha $GIT_SHA"

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

printf '{"built":true,"dry_run":%s,"version":"%s","build":"%s","sha":"%s"}\n' \
  "$([ "$DRY_RUN" = 1 ] && echo true || echo false)" "$MARKETING_VERSION" "$BUILD_NUMBER" "$GIT_SHA"
