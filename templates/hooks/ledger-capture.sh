#!/bin/bash
# living-ledger — UserPromptSubmit hook: notice a conversation that is exploring directions or
# settling decisions, and log it (in the git dir, never the repo, never the prompt text) so
# /ledger-tidy can report how often a ledger record followed. CAPTURE=measure (the default) is
# silent; CAPTURE=nudge also adds one line telling Claude to offer to record what is settled or
# open; CAPTURE=off in ledger.conf turns it off. Headless runs are silent and unlogged.
#
# Emits {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}
# in nudge mode, and nothing otherwise. ~50 ms, no model, no network.
#
# ledger-template-version: 12
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/_ledger_lib.sh"
ll_interactive || exit 0
REPO="$(ll_repo_root)" || exit 0
PYTHONDONTWRITEBYTECODE=1 exec python3 "$HERE/_ledger_parse.py" capture-hook "$REPO"
