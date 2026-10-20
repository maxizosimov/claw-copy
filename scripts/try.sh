#!/usr/bin/env bash
# Builds and runs any branch of this repository without touching your working copy.
#
#   ./scripts/try.sh                          # latest main
#   ./scripts/try.sh feature/clipboard-history
#
# What it does:
#   1. fetches the branch from origin (your GitHub repo),
#   2. checks it out in a separate worktree (~/Library/Caches/claw-copy/try),
#   3. builds and signs it with scripts/build-app.sh (your local signing certificate),
#   4. quits the running Claw Copy, installs the build as ~/Applications/Claw Copy.app, opens it.
#
# The app always has the same name, bundle ID, signature and location, so the Accessibility
# permission and the login item keep working whichever branch you try.
#
# Only branches of origin are accepted, never pull requests from forks: this runs the code
# it builds, so only build branches you trust.
set -euo pipefail
cd "$(dirname "$0")/.."

BRANCH="${1:-main}"
REMOTE="origin"
WORKTREE="$HOME/Library/Caches/claw-copy/try"
INSTALL_DIR="$HOME/Applications"
APP_NAME="Claw Copy.app"
BUNDLE_ID="com.maxizosimov.ClawCopy"

if [[ "$BRANCH" == -* ]] || ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
  echo "Not a valid branch name: $BRANCH" >&2
  exit 2
fi

git fetch --quiet "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH"
COMMIT="$(git rev-parse --verify --quiet "refs/remotes/$REMOTE/$BRANCH^{commit}")"
echo "Trying $BRANCH at $(git log -1 --format='%h "%s" by %an' "$COMMIT")"

# A detached worktree: no local branch is created or changed.
if git -C "$WORKTREE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$WORKTREE" checkout --quiet --force --detach "$COMMIT"
  git -C "$WORKTREE" clean -fdxq -e .build   # keep SwiftPM's build cache for fast rebuilds
else
  git worktree prune
  mkdir -p "$(dirname "$WORKTREE")"
  git worktree add --quiet --force --detach "$WORKTREE" "$COMMIT"
fi

"$WORKTREE/scripts/build-app.sh"

if pgrep -x ClawCopy >/dev/null; then
  echo "Quitting the running Claw Copy…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || pkill -x ClawCopy || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x ClawCopy >/dev/null || break
    sleep 0.5
  done
fi

mkdir -p "$INSTALL_DIR"
rm -rf "${INSTALL_DIR:?}/$APP_NAME"
ditto "$WORKTREE/build/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
open "$INSTALL_DIR/$APP_NAME"
echo "Running $BRANCH ($(git rev-parse --short "$COMMIT")) from $INSTALL_DIR/$APP_NAME"
