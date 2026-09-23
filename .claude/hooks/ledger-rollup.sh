#!/bin/bash
# living-ledger — regenerate this repo's block in the local cross-repo mirror
# (~/.claude/ledger/repos/<id>.md) and keep the registry row current.
#
# No git operations here — /ledger-status handles pull/commit/push. This just keeps
# the local mirror warm so the dashboard is current between status runs.
#
# ledger-template-version: 4
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_ledger_lib.sh"

REPO="$(ll_repo_root)"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0
LEDGER="$(ll_find_ledger "$REPO")"
[ -n "$LEDGER" ] && [ -f "$LEDGER" ] || exit 0

HOME_DIR="$(ll_ledger_home)"
mkdir -p "$HOME_DIR/repos" "$HOME_DIR/.local" 2>/dev/null || exit 0

ID="$(ll_repo_id "$REPO")"
HEAD_SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '')"
LEDGER_REL="${LEDGER#$REPO/}"

if [ -n "$(git -C "$REPO" status --porcelain -- "$LEDGER_REL" 2>/dev/null)" ]; then
  STATE="ledger uncommitted"
else
  STATE="clean"
fi
SINCE="$(ll_commits_since_last_entry "$REPO" "$LEDGER")"

VERSION="$(ll_repo_version "$REPO")"
MAX_OPEN="${LL_MAX_OPEN:-22}"

# the block reflects every trailer in history, synced into a copy — never the working tree
VIEW="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/ll-roll-$$")"
cp "$LEDGER" "$VIEW" && LL_LEDGER_FILE="$VIEW" LL_DECISIONS_FILE="" \
  "$HERE/ledger-sync.sh" >/dev/null 2>&1 || true
PYTHONDONTWRITEBYTECODE=1 python3 "$HERE/_ledger_parse.py" block \
  "$VIEW" "$ID" "$REPO" "$HEAD_SHA" "$STATE" "$SINCE" "$VERSION" "$MAX_OPEN" \
  > "$HOME_DIR/repos/$ID.md.tmp" 2>/dev/null && mv "$HOME_DIR/repos/$ID.md.tmp" "$HOME_DIR/repos/$ID.md"
rm -f "$VIEW"

# registry row: repo_id \t remote_url \t ledger_relpath \t first_seen_date
REG="$HOME_DIR/registry.tsv"
REMOTE="$(git -C "$REPO" remote get-url origin 2>/dev/null || echo '-')"
touch "$REG"
if ! grep -q "^$ID	" "$REG" 2>/dev/null; then
  printf '%s\t%s\t%s\t%s\n' "$ID" "$REMOTE" "$LEDGER_REL" "$(date +%Y-%m-%d)" >> "$REG"
fi

# per-machine path map (gitignored)
PATHS="$HOME_DIR/.local/paths.tsv"
touch "$PATHS"
if ! grep -q "^$ID	" "$PATHS" 2>/dev/null; then
  printf '%s\t%s\n' "$ID" "$REPO" >> "$PATHS"
fi

exit 0
