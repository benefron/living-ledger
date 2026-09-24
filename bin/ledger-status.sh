#!/usr/bin/env bash
# living-ledger — aggregate every registered repo into the cross-repo dashboard.
#
#   ledger-status.sh [--sync] [--rebuild] [--no-git] [name ...]
#
# Reads ~/.claude/ledger/.local/paths.tsv, refreshes each repo's dashboard block,
# regenerates DASHBOARD.md, and (when the index has a git remote) pulls before /
# commits + pushes after. Prints the combined digest to stdout.
#
# Read-only in every repo: each block is built from the repo's ledger PLUS any trailers its
# history holds that the committed ledger has not caught up with (synced into a temp copy),
# so nothing in any working tree is ever modified. `--sync` is accepted and ignored (v3 used
# it to write those entries into each repo; v4 never writes outside a commit).
#
# ledger-template-version: 6
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SKILL_DIR/lib/common.sh"

HOME_DIR="$(ll_ledger_home)"
REPOS="$HOME_DIR/repos"
PATHS="$HOME_DIR/.local/paths.tsv"
REG="$HOME_DIR/registry.tsv"
mkdir -p "$REPOS" "$HOME_DIR/.local"

REBUILD=0 SYNC=0 GIT=1 FILTER=""
for a in "$@"; do
  case "$a" in
    --sync)    SYNC=1 ;;
    --no-sync) SYNC=0 ;;   # accepted for compatibility; this is the default
    --rebuild) REBUILD=1 ;;
    --no-git)  GIT=0 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *)  FILTER="$FILTER $a" ;;
  esac
done

has_remote() { git -C "$HOME_DIR" remote get-url origin >/dev/null 2>&1; }

# --- pull -----------------------------------------------------------------
if [ "$GIT" = 1 ] && has_remote; then
  ll_ensure_index_drivers "$HOME_DIR" "$SKILL_DIR/templates/hooks/ledger-merge.py"
  if [ -n "$(git -C "$HOME_DIR" status --porcelain 2>/dev/null)" ]; then
    git -C "$HOME_DIR" add -A >/dev/null 2>&1
    git -C "$HOME_DIR" commit -q --no-verify -m "chore: ledger index sync $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1
  fi
  if ! git -C "$HOME_DIR" pull --rebase --quiet >/dev/null 2>&1; then
    git -C "$HOME_DIR" rebase --abort >/dev/null 2>&1
    echo "note: index pull skipped (offline, or a conflict it could not merge) — using local cache" >&2
  fi
fi

# --- refresh each registered repo --------------------------------------
seen=""
if [ -f "$PATHS" ]; then
  while IFS=$'\t' read -r id path; do
    [ -n "$id" ] || continue
    if [ -n "$FILTER" ]; then
      case " $FILTER " in *" $id "*) : ;; *) continue ;; esac
    fi
    seen="$seen $id"
    if [ ! -d "$path/.git" ]; then
      echo "gone: $id — $path (not on this machine or deleted)" >&2
      continue
    fi
    if [ -f "$path/.claude/hooks/ledger-rollup.sh" ]; then
      CLAUDE_PROJECT_DIR="$path" bash "$path/.claude/hooks/ledger-rollup.sh" >/dev/null 2>&1 || true
    fi
  done < "$PATHS"
fi

# --- rebuild: drop blocks whose id left the registry -------------------
if [ "$REBUILD" = 1 ] && [ -f "$REG" ]; then
  for f in "$REPOS"/*.md; do
    [ -e "$f" ] || continue
    bid="$(basename "$f" .md)"
    grep -q "^$bid	" "$REG" 2>/dev/null || { echo "pruned stale block: $bid" >&2; rm -f "$f"; }
  done
fi

# --- regenerate DASHBOARD.md -----------------------------------------
SKILLV="$(ll_skill_version)"
BEHIND=""
if [ -n "$SKILLV" ]; then
  for f in "$REPOS"/*.md; do
    [ -e "$f" ] || continue
    v="$(sed -n 's/.*template v\([0-9a-z]*\).*/\1/p' "$f" | head -1)"
    id="$(basename "$f" .md)"
    case "$v" in
      "")       BEHIND="${BEHIND}  - $id — template v1–v2 (its block predates version stamps)
" ;;
      unknown)  BEHIND="${BEHIND}  - $id — unstamped template
" ;;
      *)        [ "$v" -lt "$SKILLV" ] 2>/dev/null && BEHIND="${BEHIND}  - $id — template v$v
" ;;
    esac
  done
fi

{
  echo "# Living Ledger — cross-repo dashboard"
  echo
  n=$(ls -1 "$REPOS"/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "_rebuilt $(date -u '+%Y-%m-%dT%H:%M:%SZ') · ${n:-0} repos_"
  echo
  if [ -n "$(printf '%s' "$BEHIND" | tr -d ' \n')" ]; then
    echo "## Behind template v$SKILLV — run \`/ledger-init --upgrade\` in each"
    echo
    printf '%s' "$BEHIND"
    echo
  fi
  # ledger records not shared yet, per machine (hosts/<host>.tsv, each written by its own machine)
  NS="$(for t in "$HOME_DIR"/hosts/*.tsv; do
          [ -e "$t" ] || continue
          h="$(basename "$t" .tsv)"
          awk -F'\t' -v h="$h" '($7 != "" && $7 != "0") || $8 != "" || $9 == "1" {
            s = "- **" h "** · " $1 " (" $3 "): "; sep = ""
            if ($7 != "" && $7 != "0") { s = s $7 " records not pushed"; sep = " · " }
            if ($8 != "") { gsub(/,/, ", ", $8); s = s sep "unmerged branches " $8; sep = " · " }
            if ($9 == "1") { s = s sep "ledger edited, not committed" }
            print s " — as of " $10 }' "$t"
        done)"
  if [ -n "$NS" ]; then
    echo "## Not shared yet — per machine"
    echo
    printf '%s\n' "$NS"
    echo
  fi
  for f in "$REPOS"/*.md; do [ -e "$f" ] || continue; cat "$f"; echo; echo; done
} > "$HOME_DIR/DASHBOARD.md"

# --- commit + push ----------------------------------------------------
# Delegated to ledger-index-push.sh so there is ONE implementation of "get the index
# off this machine", shared with the SessionStart / SessionEnd hooks.
if [ "$GIT" = 1 ]; then
  "$SKILL_DIR/templates/hooks/ledger-index-push.sh" >&2 || true
fi

# --- print the digest ------------------------------------------------
if [ -z "$FILTER" ]; then
  cat "$HOME_DIR/DASHBOARD.md"
else
  echo "# Living Ledger — $(echo "$FILTER" | xargs)"
  echo
  for id in $FILTER; do
    [ -f "$REPOS/$id.md" ] && { cat "$REPOS/$id.md"; echo; } || echo "no block for '$id'"
  done
fi
