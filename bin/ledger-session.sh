#!/bin/bash
# living-ledger — user-level SessionStart hook (installed by `install.sh --global-only`).
#
# The per-repo digest hook only exists in repos that already have a ledger, and only v3+
# copies of it can say "you are behind". This one runs in every session and covers the gaps:
#
#   * a git repo with no ledger       -> one line suggesting /ledger-init (once per repo per
#                                        machine; `touch <repo>/.claude/.ledger-nudged` or
#                                        LEDGER_NUDGE=off silences it)
#   * a ledger on template v0-v2      -> LEDGER UPGRADE AVAILABLE (v3+ repos say it themselves)
#
# Silent in headless runs, outside git repos, and whenever there is nothing to say.
#
# ledger-template-version: 6
set -uo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SKILL_DIR/lib/common.sh"

ll_interactive || exit 0
INPUT="$(cat 2>/dev/null || true)"
CWD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")' 2>/dev/null)"
[ -n "$CWD" ] || CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0

emit() {
  printf '%s' "$1" | python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": sys.stdin.read()}}))'
}

LEDGER="$(ll_find_ledger "$ROOT")"
if [ -z "$LEDGER" ] || [ ! -f "$LEDGER" ]; then
  case "${LEDGER_NUDGE:-}" in off|0|no) exit 0 ;; esac
  [ -f "$ROOT/.claude/.ledger-nudged" ] && exit 0
  SEEN="$(ll_ledger_home)/.local/nudged.tsv"
  grep -qxF "$ROOT" "$SEEN" 2>/dev/null && exit 0
  mkdir -p "$(dirname "$SEEN")" 2>/dev/null && printf '%s\n' "$ROOT" >> "$SEEN"
  emit "No living ledger in this repo. If its decisions are worth keeping across sessions, offer \`/ledger-init\` (in one line, before the first commit). This reminder is shown once per repo."
  exit 0
fi

V="$(ll_repo_version "$ROOT")"
case "$V" in
  unknown|0|1|2)
    SV="$(ll_skill_version)"
    [ -n "$SV" ] || exit 0
    case "$V" in 0) OLD="v0 (hooks missing)" ;; unknown) OLD="an unstamped template" ;; *) OLD="v$V" ;; esac
    emit "LEDGER UPGRADE AVAILABLE: this repo runs ledger template $OLD; v$SV is installed on this machine — run \`/ledger-init --upgrade\` before the first commit of the session (adds — $(ll_changes_since "$V" "$SV"))." ;;
esac
exit 0
