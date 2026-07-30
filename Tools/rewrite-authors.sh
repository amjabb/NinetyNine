#!/bin/bash
#
# Replace the author/committer email across all commits.
#
# Used once, before the repo went public, to swap a personal address for a
# GitHub noreply one. Kept in the repo so the change is documented rather than
# mysterious.
#
# Usage:
#   Tools/rewrite-authors.sh <old-email> <new-email> [new-name]
#
# This REWRITES HISTORY. Every commit hash changes. Safe before the first push;
# after a push it requires a force-push and breaks anyone else's clone.
#
set -euo pipefail

OLD="${1:?usage: rewrite-authors.sh <old-email> <new-email> [new-name]}"
NEW="${2:?usage: rewrite-authors.sh <old-email> <new-email> [new-name]}"
NAME="${3:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is dirty — commit or stash first." >&2
  exit 1
fi

echo "==> Rewriting $OLD -> $NEW across $(git rev-list --count HEAD) commits"

FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter "
if [ \"\$GIT_AUTHOR_EMAIL\" = '$OLD' ]; then
    export GIT_AUTHOR_EMAIL='$NEW'
    $( [ -n "$NAME" ] && echo "export GIT_AUTHOR_NAME='$NAME'" )
fi
if [ \"\$GIT_COMMITTER_EMAIL\" = '$OLD' ]; then
    export GIT_COMMITTER_EMAIL='$NEW'
    $( [ -n "$NAME" ] && echo "export GIT_COMMITTER_NAME='$NAME'" )
fi
" --tag-name-filter cat -- --branches --tags

# Point future commits at the new address too, so this doesn't regress.
git config user.email "$NEW"
[ -n "$NAME" ] && git config user.name "$NAME"

# filter-branch leaves the originals in refs/original; drop them so the old
# address isn't still reachable in the repo.
rm -rf .git/refs/original
git reflog expire --expire=now --all
git gc --prune=now --quiet

echo "==> Done. Authors now:"
git log --format='  %h  %an <%ae>'

echo
echo "Verify no trace of the old address remains:"
if git log --format='%ae %ce' | grep -q "$OLD"; then
  echo "  FAILED — '$OLD' still present" >&2
  exit 1
else
  echo "  clean — '$OLD' does not appear in any commit"
fi
