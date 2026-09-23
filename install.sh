#!/usr/bin/env bash
# living-ledger — idempotent installer.
#
#   install.sh --global-only
#       (re)install the global slash-commands and initialise ~/.claude/ledger/
#
#   install.sh <repo> [--ledger-path REL] [--seed SHA] [--adopt] [--upgrade] [--quiet]
#       scaffold / upgrade the ledger in <repo>: LEDGER.md, DECISIONS.md, hooks, git hooks,
#       settings.json, merge driver, rules dir, ledger.conf, and registration in the
#       cross-repo index. --seed SHA: derive entries from trailers AFTER this commit
#       (default: HEAD, i.e. track forward). --upgrade also commits the result with a
#       Decision: trailer recording the bump.
#
# Everything here is deterministic plumbing. Interactive choices (where the ledger
# lives, whether to backfill) are made by the /ledger-init command before it calls
# this script with the flags decided.
#
# ledger-template-version: 4
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SKILL_DIR/templates"
COMMANDS_SRC="$SKILL_DIR/commands"
QUIET=0
LL_TEMPLATE_VERSION=4
say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }      # never silenced by --quiet

# shellcheck source=/dev/null
. "$SKILL_DIR/lib/common.sh"

# --- global bits: commands + ledger home ----------------------------------
install_global() {
  local cmd_dst; cmd_dst="$(ll_claude_home)/commands"
  mkdir -p "$cmd_dst"
  local f
  for f in "$COMMANDS_SRC"/*.md; do
    [ -e "$f" ] || continue
    install -m 0644 "$f" "$cmd_dst/$(basename "$f")"
  done
  say "· commands  -> $cmd_dst/  ($(ls -1 "$COMMANDS_SRC" | wc -l | tr -d ' ') files)"

  local home; home="$(ll_ledger_home)"
  mkdir -p "$home/repos" "$home/.local"
  [ -f "$home/repos/.gitkeep" ] || : > "$home/repos/.gitkeep"
  [ -f "$home/.gitignore" ] || printf '.local/\n*.tmp\n' > "$home/.gitignore"
  [ -f "$home/registry.tsv" ] || : > "$home/registry.tsv"
  ll_ensure_index_drivers "$home" "$SKILL_DIR/templates/hooks/ledger-merge.py"
  if [ ! -f "$home/DASHBOARD.md" ]; then
    printf '# Living Ledger — cross-repo dashboard\n\n_run `/ledger-status` to populate_\n' \
      > "$home/DASHBOARD.md"
  fi
  say "· index home -> $home/"

  # user-level SessionStart hook: the "no ledger here" nudge and the upgrade flag for repos
  # whose own (older) hooks cannot raise it
  [ "${LL_NO_GLOBAL_HOOK:-0}" = 1 ] && return 0
  local settings; settings="$(ll_claude_home)/settings.json"
  python3 - "$settings" "$SKILL_DIR/bin/ledger-session.sh" <<'PYG' && say "· session   -> SessionStart hook in $settings"
import json, os, sys
p, script = sys.argv[1], sys.argv[2]
cfg = {}
if os.path.exists(p):
    try:
        cfg = json.load(open(p))
    except Exception:
        print("!! %s is not valid JSON — add a SessionStart hook running %s by hand" % (p, script))
        sys.exit(1)
ss = cfg.setdefault("hooks", {}).setdefault("SessionStart", [])
for blk in ss:
    for h in blk.get("hooks", []):
        if "ledger-session.sh" in h.get("command", ""):
            h["command"] = '"%s"' % script
            break
    else:
        continue
    break
else:
    ss.append({"matcher": "startup", "hooks": [{"type": "command", "command": '"%s"' % script,
                                                "timeout": 10}]})
json.dump(cfg, open(p, "w"), indent=2)
open(p, "a").write("\n")
PYG
}

# --- settings.json hook merge -------------------------------------------
merge_settings() {
  local repo="$1" settings="$1/.claude/settings.json"
  mkdir -p "$repo/.claude"
  [ -f "$settings" ] || echo '{}' > "$settings"
  python3 - "$settings" "$QUIET" <<'PY'
import json, sys
p = sys.argv[1]
try:
    cfg = json.load(open(p))
    if not isinstance(cfg, dict):
        raise ValueError
except Exception:
    print("!! settings.json is not valid JSON — add these SessionStart hooks by hand:")
    print('   sh -c \'D="${CLAUDE_PROJECT_DIR:-.}"; "$D/.claude/hooks/digest.sh"\'')
    sys.exit(0)

def cmd(script):
    return 'sh -c \'D="${CLAUDE_PROJECT_DIR:-.}"; "$D/.claude/hooks/%s"\'' % script

CMD = cmd("digest.sh")
PUSH = cmd("ledger-index-push.sh")
want = [
    ("startup|resume|clear", "Loading project ledger…"),
    ("compact",              "Restoring ledger after compaction…"),
]
hooks = cfg.setdefault("hooks", {})
ss = hooks.setdefault("SessionStart", [])

def has(blocks, matcher, needle):
    for blk in blocks:
        if matcher is not None and blk.get("matcher") != matcher:
            continue
        for h in blk.get("hooks", []):
            if needle in h.get("command", ""):
                return True
    return False

added = 0
for matcher, msg in want:
    if has(ss, matcher, "digest.sh"):
        continue
    ss.append({"matcher": matcher, "hooks": [
        {"type": "command", "command": CMD, "timeout": 20, "statusMessage": msg}]})
    added += 1

# SessionEnd: push the cross-repo index out before the session is gone.
se = hooks.setdefault("SessionEnd", [])
if not has(se, None, "ledger-index-push.sh"):
    se.append({"matcher": "*", "hooks": [
        {"type": "command", "command": PUSH, "timeout": 25,
         "statusMessage": "Pushing ledger index…"}]})
    added += 1

json.dump(cfg, open(p, "w"), indent=2)
open(p, "a").write("\n")
if sys.argv[2] != "1":
    print(f"· settings.json -> SessionStart hooks ({'added '+str(added) if added else 'already present'})")
PY
}

# --- LEDGER.md header upgrade -------------------------------------------
# Adds standard paragraphs a v1/v2 ledger does not have yet (the Lore paragraph, the
# three-levels block). Strictly additive, and only to the HEADER: everything from
# <!-- ENTRIES_START --> onwards is copied through byte for byte, and a repo's own
# customisations (its grep examples, its workstream column, its extra sections) are
# never rewritten.
upgrade_ledger_header() {
  local ledger="$1" dec_rel="$2"
  python3 "$SKILL_DIR/lib/upgrade_header.py" "$ledger" "$dec_rel" \
    "$TPL/fragments/lore.md" "$TPL/fragments/three-levels.md"
}

# --- per-repo install --------------------------------------------------
install_repo() {
  local repo ledger_rel="" seed="" adopt=0 upgrade=0
  repo="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --ledger-path) ledger_rel="$2"; shift 2 ;;
      --seed)        seed="$2"; shift 2 ;;
      --adopt)       adopt=1; shift ;;
      --upgrade)     upgrade=1; adopt=1; shift ;;
      --quiet)       QUIET=1; shift ;;
      *) echo "install_repo: unknown flag $1" >&2; exit 2 ;;
    esac
  done

  repo="$(cd "$repo" && git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "!! not a git repository — run 'git init' first" >&2; exit 3; }
  say "living-ledger: installing into $repo"
  local was_version; was_version="$(ll_repo_version "$repo")"

  [ -n "$ledger_rel" ] || {
    local found; found="$(ll_find_ledger "$repo")"
    if [ -n "$found" ]; then ledger_rel="${found#$repo/}"; else
      ledger_rel="$(ll_default_ledger_rel "$repo")"
    fi
  }
  # The sync floor: entries are derived from trailers of commits AFTER it. Committed in
  # ledger.conf, so identical on every clone. An upgrade keeps the existing floor (or
  # migrates the old per-machine bookmark); a fresh install tracks forward from HEAD.
  [ -n "$seed" ] || seed="$(ll_sync_floor "$repo")"
  [ -n "$seed" ] || seed="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$seed" ] && ! git -C "$repo" cat-file -e "${seed}^{commit}" 2>/dev/null; then
    warn "!! sync floor $seed is not a commit here — scanning recent history instead"
    seed=""
  fi

  local repo_id; repo_id="$(ll_repo_id "$repo")"
  local ledger_abs="$repo/$ledger_rel"

  # level-2 decisions record: beside the ledger, unless one is already configured
  local dec_rel; dec_rel="$(ll_conf_get "$repo" DECISIONS_PATH)"
  if [ -z "$dec_rel" ]; then
    case "$ledger_rel" in
      */*) dec_rel="${ledger_rel%/*}/DECISIONS.md" ;;
      *)   dec_rel="DECISIONS.md" ;;
    esac
  fi
  local dec_abs="$repo/$dec_rel"

  # 1. ledger.conf — rendered from the template; any other KEY=value the repo had set by
  #    hand (AUDIENCE_SURFACE, …) is carried over, never dropped.
  mkdir -p "$repo/.claude"
  local conf="$repo/.claude/ledger.conf" oldconf=""
  [ -f "$conf" ] && oldconf="$(cat "$conf")"
  sed -e "s|__LEDGER_PATH__|$ledger_rel|" -e "s|__REPO_ID__|$repo_id|" \
      -e "s|__DECISIONS_PATH__|$dec_rel|" -e "s|__SYNC_FROM__|$seed|" \
    "$TPL/ledger.conf" > "$conf"
  if [ -n "$oldconf" ]; then
    printf '%s\n' "$oldconf" | grep -E '^[A-Z_]+=' | while IFS= read -r kv; do
      grep -q "^${kv%%=*}=" "$conf" || printf '%s\n' "$kv" >> "$conf"
    done
  fi
  say "· ledger.conf -> LEDGER_PATH=$ledger_rel  DECISIONS_PATH=$dec_rel  REPO_ID=$repo_id  SYNC_FROM=${seed:-<none>}"

  # 1b. automation that commits (a pipeline, a cron job) must not be stopped by the gate: any
  #     subject repeated >= 5 times without a ledger trailer in the last 300 commits is exempted
  #     — once, on first install; the list stays editable in ledger.conf.
  if ! grep -q '^EXEMPT_SUBJECTS=' "$conf"; then
    local exs
    exs="$(git -C "$repo" log -n300 --no-merges --format='%s%x1f%B%x1e' 2>/dev/null | python3 -c '
import re, sys, collections
keys = re.compile(r"^(Decision|Finding|Opens|Fixed|Action|Retires|Closes|Supersedes|Refs|Ledger):", re.M)
c = collections.Counter()
for rec in sys.stdin.read().split("\x1e"):
    subj, _, body = rec.strip("\n").partition("\x1f")
    if subj and not keys.search(body) and not re.match(r"(chore|docs): (ledger|sync ledger)", subj):
        c[subj] += 1
auto = sorted(s for s, n in c.items() if n >= 5)
if auto:
    print("^(" + "|".join(re.escape(s) for s in auto) + ")$")
' 2>/dev/null || true)"
    if [ -n "$exs" ]; then
      printf '\n# Commits by automation (detected at install: repeated subjects with no trailer) are\n# exempt from the ledger gate. A regex on the subject; edit freely.\nEXEMPT_SUBJECTS="%s"\n' "$exs" >> "$conf"
      warn "· exempted automated commits from the gate: $exs  (EXEMPT_SUBJECTS in .claude/ledger.conf)"
    fi
  fi

  # 2. LEDGER.md (create only; entries are NEVER rewritten). On an upgrade the only
  #    thing touched is the header: standard paragraphs that are missing get added.
  if [ -f "$ledger_abs" ]; then
    say "· LEDGER.md   -> exists, left untouched$([ $adopt = 1 ] && echo ' (adopting)')"
    local hdr; hdr="$(upgrade_ledger_header "$ledger_abs" "$dec_rel")"
    [ -n "$hdr" ] && say "· LEDGER.md   -> header upgraded: $hdr"
  else
    mkdir -p "$(dirname "$ledger_abs")"
    sed -e "s|__LEDGER_PATH__|$ledger_rel|g" -e "s|__DECISIONS_PATH__|$dec_rel|g" \
      "$TPL/LEDGER.md" > "$ledger_abs"
    say "· LEDGER.md   -> created at $ledger_rel"
  fi

  # 2b. DECISIONS.md (level 2) -- create only, never rewritten
  if [ -f "$dec_abs" ]; then
    say "· DECISIONS   -> exists at $dec_rel, left untouched"
  else
    mkdir -p "$(dirname "$dec_abs")"
    sed -e "s|__LEDGER_PATH__|$ledger_rel|g" "$TPL/DECISIONS.md" > "$dec_abs"
    say "· DECISIONS   -> created at $dec_rel (level 2: the reasoning)"
  fi

  # 3. hooks + lib + parser
  mkdir -p "$repo/.claude/hooks"
  install -m 0755 "$TPL/hooks/digest.sh"        "$repo/.claude/hooks/digest.sh"
  install -m 0755 "$TPL/hooks/ledger-sync.sh"   "$repo/.claude/hooks/ledger-sync.sh"
  install -m 0755 "$TPL/hooks/ledger-rollup.sh" "$repo/.claude/hooks/ledger-rollup.sh"
  install -m 0755 "$TPL/hooks/ledger-index-push.sh" "$repo/.claude/hooks/ledger-index-push.sh"
  install -m 0644 "$TPL/hooks/_ledger_parse.py" "$repo/.claude/hooks/_ledger_parse.py"
  install -m 0755 "$TPL/hooks/ledger-merge.py"  "$repo/.claude/hooks/ledger-merge.py"
  install -m 0755 "$TPL/hooks/ledger-activate.sh" "$repo/.claude/hooks/ledger-activate.sh"
  install -m 0644 "$SKILL_DIR/lib/common.sh"    "$repo/.claude/hooks/_ledger_lib.sh"
  say "· hooks       -> .claude/hooks/ (digest, ledger-sync, ledger-rollup, index-push, merge driver, lib, parser)"

  # 3c. entry-wise merge driver: .gitattributes is committed, the driver is per-clone config
  local ga="$repo/.gitattributes" p
  touch "$ga"
  for p in "$ledger_rel" "$dec_rel"; do
    p="$(printf '%s' "$p" | sed 's/ /[[:space:]]/g')"
    grep -qxF "$p merge=ledger" "$ga" || printf '%s merge=ledger\n' "$p" >> "$ga"
  done
  ll_ensure_merge_driver "$repo"
  say "· merge       -> .gitattributes merge=ledger (entries merge by id across branches and clones)"

  # 3a. git hooks — the enforcement half. Committed to the repo (.githooks/) so every clone
  #     gets them; a per-clone shim in the clone's own hooks dir is what makes git run them
  #     (never core.hooksPath, which would silently switch off Git LFS & co.).
  mkdir -p "$repo/.githooks"
  install -m 0755 "$TPL/githooks/commit-msg"  "$repo/.githooks/commit-msg"
  install -m 0755 "$TPL/githooks/post-commit" "$repo/.githooks/post-commit"
  local act
  if act="$(ll_activate_git_hooks "$repo")"; then
    say "· git hooks   -> .githooks/ + ${act:-already active} (commit-msg gates, post-commit syncs)"
  else
    warn "!! core.hooksPath is '$(git -C "$repo" config --get core.hooksPath)' — the ledger hooks are"
    warn "   NOT active. Chain .githooks/commit-msg and .githooks/post-commit from there by hand."
  fi

  # 3a'. the ledger files must be committable: un-ignore them if a broad .gitignore rule hides them
  local f
  for f in "$ledger_rel" "$dec_rel"; do
    if git -C "$repo" check-ignore -q -- "$f" 2>/dev/null; then
      printf '\n# living-ledger: the ledger must be committed\n!%s\n' "$f" >> "$repo/.gitignore"
      if git -C "$repo" check-ignore -q -- "$f" 2>/dev/null; then
        warn "!! $f is gitignored (a parent directory is excluded) — fix .gitignore by hand"
      else
        say "· .gitignore  -> un-ignored $f"
      fi
    fi
  done

  # 3a''. a PUBLIC remote publishes every decision, finding and reason — say so, loudly
  local remote; remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  case "$remote" in
    *github.com*)
      if command -v gh >/dev/null 2>&1; then
        local slug; slug="$(printf '%s' "$remote" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
        if [ "$(gh repo view "$slug" --json isPrivate -q .isPrivate 2>/dev/null)" = "false" ]; then
          warn "!! $slug is PUBLIC: the ledger, DECISIONS.md and every trailer will be public too."
          warn "   Keep personal or strategic reasoning out of them, or keep this ledger elsewhere."
        fi
      fi ;;
  esac

  # 3b. machine-local state: the nudge flag and bytecode. The v2/v3 per-machine sync
  #     bookmark is retired — SYNC_FROM in ledger.conf replaced it.
  local gi="$repo/.claude/.gitignore"
  touch "$gi"
  grep -qx '.ledger-nudged'  "$gi" || echo '.ledger-nudged'  >> "$gi"
  grep -qx 'hooks/__pycache__/' "$gi" || echo 'hooks/__pycache__/' >> "$gi"
  if [ -f "$repo/.claude/.ledger-sync" ]; then
    rm -f "$repo/.claude/.ledger-sync"
    say "· sync state  -> per-machine bookmark retired (SYNC_FROM=$seed is committed instead)"
  fi

  # 4. settings.json
  merge_settings "$repo"

  # 5. rules dir
  mkdir -p "$repo/.claude/rules"
  [ -f "$repo/.claude/rules/README.md" ] || \
    install -m 0644 "$TPL/rules/README.md" "$repo/.claude/rules/README.md"
  say "· rules       -> .claude/rules/"

  # 5b. one version everywhere: normalise any stale stamp install did not overwrite
  local vf
  for vf in "$repo"/.claude/ledger.conf "$repo"/.claude/hooks/* "$repo"/.githooks/* \
            "$repo"/.claude/rules/README.md; do
    [ -f "$vf" ] || continue
    if grep -q 'ledger-template-version: [0-9]' "$vf" 2>/dev/null; then
      perl -pi -e "s/ledger-template-version: \\d+/ledger-template-version: $LL_TEMPLATE_VERSION/" "$vf"
    fi
  done
  say "· version     -> ledger-template-version: $LL_TEMPLATE_VERSION everywhere"

  # 6. register in the cross-repo index
  install_global >/dev/null
  CLAUDE_PROJECT_DIR="$repo" "$repo/.claude/hooks/ledger-rollup.sh" >/dev/null 2>&1 || true
  say "· registered  -> $(ll_ledger_home)/repos/$repo_id.md"

  # 7. backfill availability
  if [ -n "$seed" ] && git -C "$repo" cat-file -e "$seed" 2>/dev/null; then
    local older; older="$(git -C "$repo" rev-list --count "$seed" 2>/dev/null || echo 0)"
    if [ "${older:-0}" -gt 0 ]; then
      say ""
      say "  $older commits predate the sync point. /ledger-init can propose backfilled"
      say "  entries from them (none / light / aggressive)."
    fi
  fi
  # 8. --upgrade: commit the upgrade. Plumbing, so `Ledger: none` — a template bump is not a
  #    project decision and must not take a "recently decided" slot in the digest.
  if [ "$upgrade" = 1 ]; then
    local wv="$was_version"
    case "$wv" in 0) wv="0 (no ledger.conf — pre-hook install)" ;; esac
    # derive what the history holds first, so the upgrade is ONE commit that leaves nothing
    CLAUDE_PROJECT_DIR="$repo" "$repo/.claude/hooks/ledger-sync.sh" >/dev/null 2>&1 || true
    if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
      # commit ONLY what the upgrade touched — never work the user already had staged
      local pth; local -a paths=()
      for pth in .claude .githooks .gitattributes .gitignore "$ledger_rel" "$dec_rel"; do
        [ -n "$pth" ] || continue
        if [ -e "$repo/$pth" ] || git -C "$repo" ls-files --error-unmatch -- "$pth" >/dev/null 2>&1; then
          git -C "$repo" add -A -- "$pth" 2>/dev/null || true
          paths+=("$pth")
        fi
      done
      LEDGER_SYNC_IN_PROGRESS=1 git -C "$repo" commit --no-verify -q \
        -m "chore: upgrade living ledger to template v$LL_TEMPLATE_VERSION" \
        -m "v$wv -> v$LL_TEMPLATE_VERSION: $(ll_version_changes "$LL_TEMPLATE_VERSION")." \
        -m "Ledger: none — living-ledger template upgrade, tooling only" \
        -- "${paths[@]}" \
        && say "· upgraded    -> committed (v$wv -> v$LL_TEMPLATE_VERSION)"
    else
      say "· upgraded    -> already at v$LL_TEMPLATE_VERSION, nothing to commit"
    fi
  fi

  say ""
  say "  Done. Every commit from here needs a ledger trailer in its trailing block:"
  say "    Decision: / Finding: / Opens: / Closes: F-x / Retires: / Supersedes: D-x / Refs: F-x"
  say "  or the explicit opt-out  'Ledger: none — <reason>'.  Escape hatch: --no-verify."
  say "  .githooks/commit-msg enforces it; .githooks/post-commit syncs + commits the ledger."
}

# --- dispatch --------------------------------------------------------
[ $# -ge 1 ] || { echo "usage: install.sh --global-only | <repo> [flags]" >&2; exit 2; }
case "$1" in
  --global-only) install_global ;;
  -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" ;;
  *) install_repo "$@" ;;
esac
