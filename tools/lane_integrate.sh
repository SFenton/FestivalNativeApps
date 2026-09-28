#!/usr/bin/env bash
# Integrate the current lane worktree into master: rebase, verify, push, retry.
#
# Usage (from inside a lane worktree, with all work committed):
#   tools/lane_integrate.sh            # swift build + tests compile + iOS build
#   tools/lane_integrate.sh --test     # also run `swift test` (feature complete)
#
# Parallel lanes push straight to origin/master. A rejected push (another lane
# landed first) triggers fetch + rebase + re-verify, up to 5 attempts.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT="$(git rev-parse --show-toplevel)"
RUN_TESTS=0
[[ "${1:-}" == "--test" ]] && RUN_TESTS=1

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "Uncommitted changes; commit first." >&2
  exit 1
fi

verify() {
  local log
  log="$(mktemp)"
  if ! (cd "$ROOT/apple" && swift build --build-tests >"$log" 2>&1); then
    grep -E "error:" "$log" | head -30 >&2
    echo "swift build failed" >&2
    return 1
  fi
  python3 "$ROOT/tools/ios_sim.py" build || { echo "iOS build failed" >&2; return 1; }
  if [[ $RUN_TESTS == 1 ]]; then
    (cd "$ROOT/apple" && swift test --parallel 2>&1 | tail -5)
  fi
}

for attempt in 1 2 3 4 5; do
  git -C "$ROOT" fetch -q origin master
  if ! git -C "$ROOT" rebase -q origin/master; then
    echo "Rebase conflict. Resolve (keep both sides' intent), 'git rebase --continue', then rerun." >&2
    exit 2
  fi
  verify
  if git -C "$ROOT" push -q origin HEAD:master; then
    echo "Integrated $(git -C "$ROOT" rev-parse --short HEAD) into master (attempt $attempt)."
    exit 0
  fi
  echo "Push rejected (another lane landed); retrying..." >&2
done
echo "Gave up after 5 attempts." >&2
exit 3
