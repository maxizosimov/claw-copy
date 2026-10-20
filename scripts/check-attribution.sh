#!/usr/bin/env bash
# Fails if AI-tool attribution appears in commit metadata or PR text.
#
#   ./scripts/check-attribution.sh <base-ref> <head-ref>
#
# PR_TITLE and PR_BODY may be passed in the environment (CI does this; they are read as
# data from env vars, never interpolated into the script).
set -euo pipefail

BASE="${1:?usage: check-attribution.sh <base-ref> <head-ref>}"
HEAD="${2:?usage: check-attribution.sh <base-ref> <head-ref>}"

pattern='co-authored-by:.*(claude|anthropic)|noreply@anthropic\.com|claude-session:|generated (with|by) \[?claude|claude\.ai/code|claude\.com/claude-code'
status=0

commits="$(git log --format='%H%n%an <%ae>%n%cn <%ce>%n%B' "$BASE..$HEAD")"
if printf '%s\n' "$commits" | grep -inE "$pattern"; then
  echo "ATTRIBUTION CHECK FAILED: AI-tool attribution found in commit metadata above." >&2
  status=1
fi

if printf '%s\n%s\n' "${PR_TITLE:-}" "${PR_BODY:-}" | grep -inE "$pattern"; then
  echo "ATTRIBUTION CHECK FAILED: AI-tool attribution found in the pull request text above." >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "Attribution check passed for $(git rev-list --count "$BASE..$HEAD") commit(s)."
fi
exit "$status"
