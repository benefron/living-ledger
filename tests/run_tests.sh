#!/usr/bin/env bash
# living-ledger — offline end-to-end test harness. No network, no display, never touches ~/.claude.
#   bash tests/run_tests.sh          (python3 tests/test_merge.py covers the merge driver alone)
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$SKILL/install.sh"
PASS=0; FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export LL_HOME_DIR="$WORK/claude"          # keep the real ~/.claude untouched
export LL_SKILL_DIR="$SKILL"               # version comparison reads the skill under test
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$WORK/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global init.defaultBranch main
git config --global advice.detachedHead false
unset CLAUDE_CODE_ENTRYPOINT LEDGER_SKIP LEDGER_DIGEST LEDGER_AUTO_HOOKS CLAUDE_PROJECT_DIR

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

ghas() {  # ghas <pattern> <git args...> — buffered: `git … | grep -q` under pipefail SIGPIPEs git
  local pat="$1"; shift
  git "$@" > "$WORK/.ghas" 2>/dev/null
  grep -q "$pat" "$WORK/.ghas"
}
NOHOOKS="$WORK/nohooks"; mkdir -p "$NOHOOKS"
newrepo() {  # newrepo <name> -> path (one root commit, no ledger)
  local d="$WORK/$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" -c core.hooksPath="$NOHOOKS" commit -q --allow-empty -m "root"
  printf '%s\n' "$d"
}
# commit(): BYPASSES the git hooks, to test the sync in isolation. hc(): through the real hooks.
commit() { local r="$1"; shift; git -C "$r" -c core.hooksPath="$NOHOOKS" commit -q --allow-empty -m "$*"; }
hc() { local r="$1"; shift; ( cd "$r" && git commit -q --allow-empty "$@" ) >"$WORK/out" 2>"$WORK/err"; }
sync_() { CLAUDE_PROJECT_DIR="$1" "$1/.claude/hooks/ledger-sync.sh" 2>"$WORK/syncerr"; }
hdrs() { sed -n '/ENTRIES_START/,$p' "$1/LEDGER.md" | grep '^## '; }
hid() { python3 "$SKILL/templates/hooks/_ledger_parse.py" id "$1" "$2"; }
digest() { CLAUDE_PROJECT_DIR="$1" bash "$1/.claude/hooks/digest.sh" 2>/dev/null | python3 -c \
  'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t.strip() else "")'; }
installed() { "$INSTALL" "$1" --quiet "${@:2}"; git -C "$1" add -A; commit "$1" "chore: install
Ledger: none — installing the ledger tooling"; }

# ---------------------------------------------------------------------------
echo "1. fresh install"
R="$(newrepo fresh)"
"$INSTALL" "$R" --quiet
check "LEDGER.md + DECISIONS.md created" "[ -f '$R/LEDGER.md' ] && [ -f '$R/DECISIONS.md' ]"
check "ledger.conf has a committed SYNC_FROM floor at HEAD" \
  "[ \"\$(sed -n s/^SYNC_FROM=//p '$R/.claude/ledger.conf')\" = \"\$(git -C '$R' rev-parse --short HEAD)\" ]"
check "no per-machine bookmark"       "[ ! -e '$R/.claude/.ledger-sync' ]"
check "hooks + merge driver present"  "[ -x '$R/.claude/hooks/digest.sh' ] && [ -x '$R/.claude/hooks/ledger-merge.py' ] && [ -x '$R/.claude/hooks/ledger-activate.sh' ]"
check "git hooks are shims in .git/hooks" "grep -q 'living-ledger shim' '$R/.git/hooks/commit-msg' && grep -q 'living-ledger shim' '$R/.git/hooks/post-commit'"
check "core.hooksPath NOT used"       "[ -z \"\$(git -C '$R' config --get core.hooksPath)\" ]"
check ".gitattributes merge=ledger"   "grep -qx 'LEDGER.md merge=ledger' '$R/.gitattributes' && grep -qx 'DECISIONS.md merge=ledger' '$R/.gitattributes'"
check "merge driver registered"       "git -C '$R' config --get merge.ledger.driver | grep -q ledger-merge.py"
check "settings.json valid, has digest" "python3 -c 'import json;d=json.load(open(\"$R/.claude/settings.json\"));assert \"digest.sh\" in json.dumps(d)'"
check "registered in the index"       "ls '$LL_HOME_DIR'/ledger/repos/*.md >/dev/null 2>&1"
check "user-level session hook added" "grep -q 'ledger-session.sh' '$LL_HOME_DIR/settings.json'"
check "every stamp is v6" "! grep -rl 'ledger-template-version: [0-57-9]' '$R/.claude' '$R/.githooks' >/dev/null"
git -C "$R" add -A; commit "$R" "chore: install
Ledger: none — installing the ledger tooling"

# ---------------------------------------------------------------------------
echo "2. vocabulary -> entries (content-hash ids)"
commit "$R" "feat: one

Decision: use a queue for the encoder
Finding: the vendor API caps requests at 10/s
Opens: the cache is never invalidated after a deploy"
commit "$R" "feat: two

Fixed: empty stanzas were silently dropped
Action: ask the vendor for a higher limit
Retires: a nightly batch job is good enough"
sync_ "$R"
check "Decision -> D-<hash> CLOSED" "grep -q \"^## $(hid D 'use a queue for the encoder') · CLOSED · decision\" '$R/LEDGER.md'"
check "Finding -> STANDING fact"    "grep -q \"^## $(hid F 'the vendor API caps requests at 10/s') · STANDING · finding\" '$R/LEDGER.md'"
check "Opens -> OPEN"               "grep -q \"^## $(hid F 'the cache is never invalidated after a deploy') · OPEN · finding\" '$R/LEDGER.md'"
check "Fixed -> CLOSED finding"     "grep -q \"^## $(hid F 'empty stanzas were silently dropped') · CLOSED · finding\" '$R/LEDGER.md'"
check "Action -> A- OPEN action"    "grep -q \"^## $(hid A 'ask the vendor for a higher limit') · OPEN · action\" '$R/LEDGER.md'"
check "Retires -> R- STANDING"      "grep -q \"^## $(hid R 'a nightly batch job is good enough') · STANDING · retired\" '$R/LEDGER.md'"
FIRST="$(hdrs "$R" | head -1)"
check "newest commit on top (Fixed first)" "printf '%s' \"\$FIRST\" | grep -q 'CLOSED · finding'"
check "decision logged to DECISIONS.md" "grep -q '| $(hid D 'use a queue for the encoder') |' '$R/DECISIONS.md'"
cp "$R/LEDGER.md" "$WORK/l1"; sync_ "$R"
check "second sync is a no-op" "cmp -s '$WORK/l1' '$R/LEDGER.md'"

# ---------------------------------------------------------------------------
echo "3. trailer reading: wrapped trailers kept, prose never parsed"
commit "$R" "docs: vocabulary

This commit describes how a Finding: or
Decision: line mid-paragraph must never be parsed as a real trailer.

Decision: wrapped trailers are joined onto one line so
a 72-column wrap never loses the entry
Refs: $(hid D 'use a queue for the encoder')"
sync_ "$R"
check "wrapped Decision captured whole" "grep -q '^wrapped trailers are joined onto one line so a 72-column wrap never loses the entry' '$R/LEDGER.md'"
check "prose line NOT captured"         "! grep -q 'line mid-paragraph must never' '$R/LEDGER.md'"

# ---------------------------------------------------------------------------
echo "4. modifiers bind to the entry above them"
commit "$R" "feat: bind

Decision: bind lore to the entry above
Rejected: copy it to every entry | noise
Opens: follow up with the vendor
Due: 2026-01-15
Owner: sam
Decision: a second decision in the same commit
Pin: yes"
commit "$R" "docs: late

Date: 2026-01-02
Area: hiring
Decision: interview loop is two rounds, decided in the planning meeting"
sync_ "$R"
blk() { awk -v id="$2" '$0 ~ "^## "id" " {p=1; print; next} /^## /{p=0} p' "$1/LEDGER.md"; }
check "Rejected on its decision"        "blk '$R' $(hid D 'bind lore to the entry above') | grep -q '· Rejected: copy it'"
check "Rejected NOT on the next one"    "! blk '$R' $(hid D 'a second decision in the same commit') | grep -q 'Rejected'"
check "Due + Owner on the open item"    "blk '$R' $(hid F 'follow up with the vendor') | grep -q '· Due: 2026-01-15' && blk '$R' $(hid F 'follow up with the vendor') | grep -q '· Owner: sam'"
check "Pin on the second decision"      "blk '$R' $(hid D 'a second decision in the same commit') | grep -qx '· Pinned'"
check "commit-wide Date -> (recorded)"  "grep -q \"^## $(hid D 'interview loop is two rounds, decided in the planning meeting') · CLOSED · decision · hiring · 2026-01-02 (recorded \" '$R/LEDGER.md'"

# ---------------------------------------------------------------------------
echo "5. Closes / Supersedes / Refs"
OPEN_ID="$(hid F 'the cache is never invalidated after a deploy')"
OLD_D="$(hid D 'use a queue for the encoder')"
commit "$R" "fix: cache

Decision: use a lock-free ring buffer for the encoder
Supersedes: $OLD_D
Closes: $OPEN_ID"
sync_ "$R"
NEW_D="$(hid D 'use a lock-free ring buffer for the encoder')"
check "Closes flips to CLOSED"          "grep -q \"^## $OPEN_ID · CLOSED\" '$R/LEDGER.md'"
check "closing commit recorded"         "blk '$R' $OPEN_ID | grep -q '^✓ closed by '"
check "Supersedes -> SUPERSEDED + ptr"  "grep -q \"^## $OLD_D · SUPERSEDED\" '$R/LEDGER.md' && blk '$R' $OLD_D | grep -q \"⤳ superseded by $NEW_D\""
check "Refs backlink from section 3"    "blk '$R' $OLD_D | grep -q '^↔ .* docs: vocabulary'"
perl -pi -e "s/^## $OPEN_ID · CLOSED/## $OPEN_ID · OPEN/" "$R/LEDGER.md"
sync_ "$R"
check "a hand re-open survives re-scans" "grep -q \"^## $OPEN_ID · OPEN\" '$R/LEDGER.md'"
commit "$R" "fix: nope

Closes: F-9999999"
sync_ "$R"
check "unknown id warns on stderr"      "grep -q 'F-9999999' '$WORK/syncerr'"

# ---------------------------------------------------------------------------
echo "5b. Closes: closes a finding; never a decision, a retired framing or a note"
C="$(newrepo closes)"; installed "$C"
commit "$C" "feat: facts

Finding: the parser drops the last line of a file with no trailing newline
Decision: keep the parser line-based
Retires: a regex over the whole file"
sync_ "$C"
FACT="$(hid F 'the parser drops the last line of a file with no trailing newline')"
DEC="$(hid D 'keep the parser line-based')"
RET="$(hid R 'a regex over the whole file')"
check "a STANDING finding shows as established"  "digest '$C' | grep -q 'drops the last line'"
commit "$C" "fix: keep the last line

Closes: $FACT"
sync_ "$C"
check "Closes: flips a STANDING finding to CLOSED" "grep -q \"^## $FACT · CLOSED\" '$C/LEDGER.md' && blk '$C' $FACT | grep -q '^✓ closed by '"
check "…and the digest stops showing it"          "! digest '$C' | grep -q 'drops the last line'"
git -C "$C" add LEDGER.md; commit "$C" "chore: ledger sync

Ledger: none — the ledger as post-commit would commit it"
perl -pi -e "s/^## $FACT · CLOSED/## $FACT · STANDING/" "$C/LEDGER.md"
sync_ "$C"
check "a hand re-open to STANDING survives re-scans" "grep -q \"^## $FACT · STANDING\" '$C/LEDGER.md'"
commit "$C" "chore: made without the gate

Closes: $DEC, $RET"
sync_ "$C"
check "sync: Closes: leaves a decision alone, and says so" "grep -q \"^## $DEC · CLOSED · decision\" '$C/LEDGER.md' && ! blk '$C' $DEC | grep -q '✓ closed' && grep -q \"Closes $DEC .*ignored\" '$WORK/syncerr'"
check "sync: …and a retired framing"                       "grep -q \"^## $RET · STANDING\" '$C/LEDGER.md' && ! blk '$C' $RET | grep -q '✓ closed' && grep -q \"Closes $RET .*ignored\" '$WORK/syncerr'"
check "sync: the ignored close is noted on the entry"      "blk '$C' $DEC | grep -q '^· not closed by ' && blk '$C' $RET | grep -q '^· not closed by '"
sync_ "$C"
check "sync: …so it is reported once, not on every re-scan" "! grep -q 'ignored' '$WORK/syncerr' && [ \"\$(blk '$C' $DEC | grep -c '^· not closed by ')\" -eq 1 ]"
check "a note is never closed either" "python3 -c \"import sys; sys.path.insert(0,'$SKILL/templates/hooks'); from _ledger_parse import close_refusal as r; assert r('STANDING','note') and r('STANDING','thought') and not r('STANDING','finding') and not r('OPEN','action') and not r('STANDING','action')\""
# a close from before this rule: a ✓ line on an entry the Closes: never changed
LEG="$(hid F 'a fact closed before Closes: flipped STANDING findings')"
commit "$C" "feat: legacy

Finding: a fact closed before Closes: flipped STANDING findings"
sync_ "$C"
perl -0pi -e "s/(^## $LEG · STANDING[^\n]*\n[^\n]*\n)/\$1✓ closed by 0000000 an old close\n/m" "$C/LEDGER.md"
perl -0pi -e "s/(^## $DEC · CLOSED[^\n]*\n[^\n]*\n)/\$1✓ closed by 0000001 an old close\n/m" "$C/LEDGER.md"
noop() { python3 "$C/.claude/hooks/_ledger_parse.py" tidy-report "$C/LEDGER.md" "$C" \
  | awk '/^## A Closes: that changed nothing/{p=1; next} /^## /{p=0} p'; }
REP="$(noop)"
check "tidy: a STANDING finding with a ✓ line -> CLOSED" "printf '%s' \"\$REP\" | grep -q \"$LEG .*→ CLOSED\""
check "tidy: a decision with a ✓ line -> Supersedes or keep" "printf '%s' \"\$REP\" | grep -q \"$DEC .*Supersedes: $DEC\""
check "tidy: a retired framing a gate-skipping Closes: named" "printf '%s' \"\$REP\" | grep -q \"$RET .*Supersedes: $RET\""
check "tidy: a finding closed, then re-opened by hand, is left alone" "! printf '%s' \"\$REP\" | grep -q \"$FACT\""
perl -0pi -e "s/(^## $DEC · (?:.+\n)+)/\$1· tidied 2026-09-24: kept in force — that commit did not end it\n/m" "$C/LEDGER.md"
REP="$(noop)"
check "tidy: …and one a tidy kept is not raised again" "! printf '%s' \"\$REP\" | grep -q \"$DEC\" && printf '%s' \"\$REP\" | grep -q \"$LEG\""
CG="$(newrepo closegate)"; installed "$CG"
hc "$CG" -m "feat: exports" -m "Finding: the export writes UTC timestamps
Decision: exports are CSV only
Retires: an XML export"
F2="$(hid F 'the export writes UTC timestamps')"; D2="$(hid D 'exports are CSV only')"; R2="$(hid R 'an XML export')"
hc "$CG" -m "x" -m "Closes: $D2";   check "gate: Closes: on a decision -> rejected (Refs / Supersedes)" "grep -q 'REJECTED.*Closes: $D2' '$WORK/err' && grep -q 'Refs: $D2' '$WORK/err' && grep -q 'Supersedes: $D2' '$WORK/err'"
hc "$CG" -m "x" -m "Closes: $R2";   check "gate: Closes: on a retired framing -> rejected (Supersedes)" "grep -q 'REJECTED.*Closes: $R2' '$WORK/err' && grep -q 'Supersedes: $R2' '$WORK/err'"
hc "$CG" -m "fix: x" -m "Closes: $F2"; check "gate: Closes: on a STANDING finding -> accepted" "[ \$? -eq 0 ]"
check "…and post-commit closes it" "grep -q \"^## $F2 · CLOSED\" '$CG/LEDGER.md'"
check "validate (history only) does not judge Closes: targets" "python3 -c \"import sys; sys.path.insert(0,'$SKILL/templates/hooks'); from _ledger_parse import check_body; assert not check_body('x\n\nCloses: $D2', '$CG', 't', structural_only=True)\""

# ---------------------------------------------------------------------------
echo "6. stateless: every clone derives the same ledger"
HDRS="$(hdrs "$R" | sort)"
cp "$SKILL/templates/LEDGER.md" "$R/LEDGER.md"
sync_ "$R"
check "regenerated from git alone: same entries" "[ \"\$(hdrs '$R' | sort | sed 's/ · OPEN · finding/ · X/;s/ · CLOSED · finding/ · X/')\" = \"\$(printf '%s\n' \"\$HDRS\" | sed 's/ · OPEN · finding/ · X/;s/ · CLOSED · finding/ · X/')\" ]"
git -C "$R" checkout -q -- LEDGER.md 2>/dev/null || true
R6="$(newrepo floor)"
commit "$R6" "feat: before

Decision: made before the ledger existed"
installed "$R6"
commit "$R6" "feat: after

Decision: made after install"
sync_ "$R6"
check "trailers before SYNC_FROM are not derived" "! grep -q 'made before the ledger existed' '$R6/LEDGER.md'"
check "trailers after it are"                     "grep -q 'made after install' '$R6/LEDGER.md'"

# ---------------------------------------------------------------------------
echo "7. the commit gate (real hooks)"
G="$(newrepo gate)"; installed "$G"
hc "$G" -m "wip";                                        check "no trailer -> rejected" "[ \$? -ne 0 ] && grep -q 'REJECTED' '$WORK/err'"
hc "$G" -m "x" -m "Ledger: none";                        check "bare Ledger: none -> rejected" "grep -q 'at least 3' '$WORK/err'"
hc "$G" -m "x" -m "Ledger: none — reformat only, no behaviour change"; check "reasoned opt-out -> ok" "[ \$? -eq 0 ]"
hc "$G" -m "x" -m "Finding: stray" -m "then prose after it."; check "trailer outside the block -> rejected" "grep -q 'silently ignored' '$WORK/err'"
hc "$G" -m "x" -m "Closes: C-014";                      check "unknown id -> rejected" "grep -q 'no entry C-014' '$WORK/err'"
hc "$G" -m "x" -m "Finding: F-1 (param race) handled";  check "id-led text -> rejected" "grep -q 'starts with an id' '$WORK/err'"
hc "$G" -m "x" -m "Opens: a real problem
Due: next week";                                          check "bad Due date -> rejected" "grep -q 'YYYY-MM-DD' '$WORK/err'"
hc "$G" -m "x" -m "Decision: a wrapped decision that goes on
and on past the column limit";                           check "wrapped trailer -> accepted" "[ \$? -eq 0 ]"
check "…and recorded whole by post-commit" "grep -q 'a wrapped decision that goes on and on past the column limit' '$G/LEDGER.md'"
( cd "$G" && GIT_AUTHOR_NAME='github-actions[bot]' git commit -q --allow-empty -m "chore: bump" ) 2>/dev/null; check "[bot] author exempt" "[ \$? -eq 0 ]"
( cd "$G" && LEDGER_SKIP=1 git commit -q --allow-empty -m "chore: cron" ) 2>/dev/null; check "LEDGER_SKIP=1 exempt" "[ \$? -eq 0 ]"
echo 'EXEMPT_SUBJECTS="^chore: local pipeline update"' >> "$G/.claude/ledger.conf"
hc "$G" -m "chore: local pipeline update";               check "EXEMPT_SUBJECTS exempt" "[ \$? -eq 0 ]"
hc "$G" -m "fixup! x";                                   check "fixup! exempt" "[ \$? -eq 0 ]"
hc "$G" -m "wip" --no-verify;                            check "--no-verify escape hatch" "[ \$? -eq 0 ]"

# ---------------------------------------------------------------------------
echo "8. post-commit: auto-sync, exactly once, only the ledger"
N0="$(git -C "$G" rev-list --count HEAD)"
echo staged > "$G/staged.txt"; git -C "$G" add staged.txt; echo dirty > "$G/dirty.txt"
( cd "$G" && git commit -q --allow-empty --only -m "decide: x" -m "Decision: record decisions with an empty commit" ) >/dev/null 2>&1
check "one trailer commit + one sync commit" "[ \$(git -C '$G' rev-list --count HEAD) -eq \$((N0 + 2)) ]"
check "sync commit subject"  "git -C '$G' log -1 --format=%s | grep -q '^chore: ledger sync (auto, after '"
check "sync commit touched only the ledger files" "[ \"\$(git -C '$G' show --format= --name-only HEAD | sort | tr '\n' ' ')\" = 'DECISIONS.md LEDGER.md ' ]"
check "staged work stays staged, unstaged stays" "git -C '$G' diff --cached --name-only | grep -qx staged.txt && [ -f '$G/dirty.txt' ]"
check "ledger clean after"   "[ -z \"\$(git -C '$G' status --porcelain -- LEDGER.md DECISIONS.md)\" ]"
git -C "$G" reset -q; rm -f "$G/staged.txt" "$G/dirty.txt"
echo "hand edit" >> "$G/LEDGER.md"
hc "$G" -m "x" -m "Decision: this lands while a hand edit is pending"
check "hand-edited ledger is NOT auto-committed" "grep -q 'hand edit' '$G/LEDGER.md' && ! git -C '$G' log -1 --format=%s | grep -q 'ledger sync'"
git -C "$G" checkout -q -- LEDGER.md; git -C "$G" add -A; commit "$G" "x
Ledger: none — test housekeeping only here"
S="$WORK/with space"; mkdir -p "$S"; git -C "$S" init -q; git -C "$S" -c core.hooksPath="$NOHOOKS" commit -q --allow-empty -m root
mkdir -p "$S/docs root"; installed "$S" --ledger-path "docs root/LEDGER.md"
printf 'docs root/*\n!docs root/LEDGER.md\n' > "$S/.gitignore"; git -C "$S" add .gitignore; commit "$S" "x
Ledger: none — gitignore that hides DECISIONS"
hc "$S" -m "x" -m "Decision: spaces and an ignored DECISIONS.md are survivable"
check "path with spaces: ledger auto-committed" "git -C '$S' log -1 --format=%s | grep -q 'ledger sync' && grep -q 'spaces and an ignored' '$S/docs root/LEDGER.md'"
check "ignored DECISIONS.md: nothing left staged" "[ -z \"\$(git -C '$S' diff --cached --name-only)\" ]"
R8="$(newrepo ign)"; printf 'docs_root/*\n!docs_root/LEDGER.md\n' > "$R8/.gitignore"; mkdir -p "$R8/docs_root"
git -C "$R8" add .gitignore; commit "$R8" "x"
"$INSTALL" "$R8" --quiet
check "install un-ignores DECISIONS.md" "! git -C '$R8' check-ignore -q docs_root/DECISIONS.md"

# ---------------------------------------------------------------------------
echo "9. git hooks: shims keep existing hooks (Git LFS) running"
H="$(newrepo lfs)"
printf '#!/bin/sh\necho lfs-ran >> "%s/lfs.log"\n' "$WORK" > "$H/.git/hooks/post-commit"; chmod +x "$H/.git/hooks/post-commit"
installed "$H"
check "existing hook kept as .pre-ledger" "[ -x '$H/.git/hooks/post-commit.pre-ledger' ]"
rm -f "$WORK/lfs.log"; hc "$H" -m "x" -m "Decision: the LFS hook still runs"
check "…and still runs" "grep -q lfs-ran '$WORK/lfs.log'"
check "…and the ledger hook ran too" "grep -q 'the LFS hook still runs' '$H/LEDGER.md'"
V3="$(newrepo v3hp)"; installed "$V3"
rm -f "$V3/.git/hooks/commit-msg" "$V3/.git/hooks/post-commit"; git -C "$V3" config core.hooksPath .githooks
"$INSTALL" "$V3" --quiet
check "v3 core.hooksPath migrated to shims" "[ -z \"\$(git -C '$V3' config --get core.hooksPath)\" ] && grep -q shim '$V3/.git/hooks/commit-msg'"
HK="$(newrepo husky)"; git -C "$HK" config core.hooksPath .husky
"$INSTALL" "$HK" --quiet > "$WORK/hk.out" 2>&1
check "foreign core.hooksPath left alone + reported" "[ \"\$(git -C '$HK' config --get core.hooksPath)\" = .husky ] && grep -q 'NOT active' '$WORK/hk.out'"
FC="$WORK/fresh-clone"; git clone -q "$H" "$FC"
check "fresh clone: hooks inactive" "! grep -q shim '$FC/.git/hooks/commit-msg' 2>/dev/null"
DG="$(digest "$FC")"
check "session start activates them and says so" "grep -q shim '$FC/.git/hooks/commit-msg' && printf '%s' \"\$DG\" | grep -q 'Activated this clone'"
FC2="$WORK/fresh-clone2"; git clone -q "$H" "$FC2"
DG="$(LEDGER_AUTO_HOOKS=0 digest "$FC2")"
check "LEDGER_AUTO_HOOKS=0: instruction only" "! grep -q shim '$FC2/.git/hooks/commit-msg' 2>/dev/null && printf '%s' \"\$DG\" | grep -q 'ledger-activate.sh'"

# ---------------------------------------------------------------------------
echo "10. the session digest"
D="$(newrepo dig)"; installed "$D"
mkdir -p "$D/src/net" "$D/docs"
commit "$D" "feat: a

Opens: a problem somewhere else
Area: docs"
commit "$D" "feat: b

Opens: late reply from the vendor
Due: 2020-01-01"
echo 1 > "$D/src/net/x.py"; git -C "$D" add -A; commit "$D" "feat: c

Opens: a problem in the network code"
commit "$D" "feat: d

Decision: this one is pinned
Pin: yes"
git -C "$D" -c core.hooksPath="$NOHOOKS" commit -q --allow-empty -m "feat: e

Opens: arrived without the hooks"
BEFORE="$(git -C "$D" status --porcelain)"
DG="$(digest "$D")"
check "digest is not empty"                   "printf '%s' \"\$DG\" | grep -q 'Project ledger digest'"
check "reading never dirties the working tree" "[ \"\$(git -C '$D' status --porcelain)\" = \"\$BEFORE\" ]"
check "un-synced trailers still shown"         "printf '%s' \"\$DG\" | grep -q 'arrived without the hooks'"
check "…and flagged as behind"                 "printf '%s' \"\$DG\" | grep -q 'behind the commit history'"
check "overdue item listed first"              "printf '%s' \"\$DG\" | sed -n '/^## Open/{n;p;}' | grep -q 'late reply'"
check "recent-area item before other areas"    "printf '%s' \"\$DG\" | awk '/network code/{a=NR} /somewhere else/{b=NR} END{exit !(a<b)}'"
check "pinned section"                         "printf '%s' \"\$DG\" | grep -A1 '^## Pinned' | grep -q 'this one is pinned'"
check "headless session (claude -p) gets nothing" "[ -z \"\$(CLAUDE_CODE_ENTRYPOINT=sdk-cli CLAUDE_PROJECT_DIR='$D' '$D/.claude/hooks/digest.sh')\" ]"
check "LEDGER_DIGEST=on overrides"             "CLAUDE_CODE_ENTRYPOINT=sdk-cli LEDGER_DIGEST=on CLAUDE_PROJECT_DIR='$D' '$D/.claude/hooks/digest.sh' | grep -q 'Project ledger digest'"
for i in $(seq 1 25); do commit "$D" "o$i

Opens: overflow item number $i"; done
check "over the cap -> triage line" "digest '$D' | grep -q 'over the digest cap'"
printf '## broken header without dots\n' >> "$D/LEDGER.md"
check "lint surfaces a malformed header" "digest '$D' | grep -q 'ledger lint: line'"
git -C "$D" checkout -q -- LEDGER.md
mkdir -p "$D/.claude/rules"
CLOSED_F="$(hid F 'a problem somewhere else')"
printf -- '---\npaths: ["x"]\n---\n- %s and %s\n' "$CLOSED_F" "$(hid D 'this one is pinned')" > "$D/.claude/rules/r.md"
commit "$D" "fix: close it

Closes: $CLOSED_F"
DG="$(digest "$D")"
check "rule citing a CLOSED finding is stale"  "printf '%s' \"\$DG\" | grep -q \"stale rule: r.md cites $CLOSED_F\""
check "rule citing an in-force decision is NOT" "! printf '%s' \"\$DG\" | grep -q \"cites $(hid D 'this one is pinned')\""
printf -- '- %s · CLOSED — do not re-raise it\n' "$CLOSED_F" > "$D/.claude/rules/r.md"
check "a rule that says the entry is CLOSED is not stale" "! digest '$D' | grep -q 'stale rule: r.md'"

# ---------------------------------------------------------------------------
echo "11. branches and clones: no id collisions, no merge conflicts"
B="$(newrepo branches)"; installed "$B"
git -C "$B" checkout -q -b feat-a; hc "$B" -m "a" -m "Decision: branch A decides this
Opens: branch A found this"
git -C "$B" checkout -q main;      hc "$B" -m "b" -m "Decision: main decides that"
git -C "$B" checkout -q -b feat-b main; hc "$B" -m "c" -m "Opens: branch B found another thing"
git -C "$B" checkout -q main
git -C "$B" merge -q --no-edit feat-a >/dev/null 2>&1; A_RC=$?
git -C "$B" merge -q --no-edit feat-b >/dev/null 2>&1; B_RC=$?
check "both merges clean (entry-wise driver)" "[ $A_RC -eq 0 ] && [ $B_RC -eq 0 ] && ! grep -q '<<<<<<<' '$B/LEDGER.md'"
check "all four entries, no duplicates" "[ \$(hdrs '$B' | wc -l) -eq 4 ] && [ -z \"\$(hdrs '$B' | cut -d' ' -f2 | sort | uniq -d)\" ]"
cp "$B/LEDGER.md" "$WORK/b1"; sync_ "$B"
check "post-merge sync changes nothing" "cmp -s '$WORK/b1' '$B/LEDGER.md'"
check "DECISIONS log merged too" "[ \$(grep -c '^| .* | D-' '$B/DECISIONS.md') -eq 2 ] && ! grep -q '<<<<<<<' '$B/DECISIONS.md'"
C2="$WORK/clone2"; git clone -q "$B" "$C2"; cp "$SKILL/templates/LEDGER.md" "$C2/LEDGER.md"; sync_ "$C2"
check "a fresh clone derives identical ids" "[ \"\$(hdrs '$C2' | cut -d' ' -f2 | sort)\" = \"\$(hdrs '$B' | cut -d' ' -f2 | sort)\" ]"

# ---------------------------------------------------------------------------
echo "12. upgrades: v1 marker and v3 bookmark -> v6, nothing lost"
U1="$(newrepo v1)"
commit "$U1" "feat: old

Decision: legacy decision one"
cat > "$U1/LEDGER.md" <<EOF
# Project Ledger

<!-- last_synced_commit: $(git -C "$U1" rev-parse --short HEAD) -->

<!-- ENTRIES_START -->

## D-001 · CLOSED · decision · - · 2026-01-01
legacy decision one
→ commit $(git -C "$U1" rev-parse --short HEAD)

## F-002 · OPEN · finding · - · 2026-01-01
legacy open finding
EOF
mkdir -p "$U1/.claude"; printf '# ledger-template-version: 1\nLEDGER_PATH=LEDGER.md\nREPO_ID=v1repo\n' > "$U1/.claude/ledger.conf"
git -C "$U1" add -A; commit "$U1" "docs: v1 ledger"
commit "$U1" "feat: pending

Decision: made after the v1 marker, not yet synced"
echo "user work" > "$U1/staged.txt"; git -C "$U1" add staged.txt
"$INSTALL" "$U1" --upgrade --quiet
check "upgrade is ONE commit, with Ledger: none" "git -C '$U1' log -1 --format=%B | grep -q '^Ledger: none'"
check "…and leaves the user's staged work out of it" "! git -C '$U1' show --name-only --format= HEAD | grep -q staged.txt && git -C '$U1' diff --cached --name-only | grep -qx staged.txt"
git -C "$U1" reset -q; rm -f "$U1/staged.txt"
check "floor = the v1 marker"                  "grep -q \"^SYNC_FROM=\" '$U1/.claude/ledger.conf'"
check "REPO_ID kept"                           "grep -qx 'REPO_ID=v1repo' '$U1/.claude/ledger.conf'"
sync_ "$U1"
check "legacy entries not duplicated"          "[ \$(grep -c 'legacy decision one' '$U1/LEDGER.md') -eq 1 ]"
check "pending trailer after the marker derived" "grep -q 'made after the v1 marker' '$U1/LEDGER.md'"
check "v1 marker stripped"                     "! grep -q last_synced_commit '$U1/LEDGER.md'"
hc "$U1" -m "fix" -m "Closes: F-002"
check "legacy ids still work in Closes:"       "grep -q '^## F-002 · CLOSED' '$U1/LEDGER.md'"
U3="$(newrepo v3)"; installed "$U3"
echo 'AUDIENCE_SURFACE=paper/main.tex' >> "$U3/.claude/ledger.conf"
sed -i.bak '/^SYNC_FROM=/d' "$U3/.claude/ledger.conf"; rm -f "$U3/.claude/ledger.conf.bak"
git -C "$U3" rev-parse --short HEAD > "$U3/.claude/.ledger-sync"
perl -pi -e 's/ledger-template-version: 6/ledger-template-version: 3/' "$U3/.claude/ledger.conf" "$U3"/.claude/hooks/*
git -C "$U3" add -A; commit "$U3" "x
Ledger: none — simulate a v3 install"
"$INSTALL" "$U3" --upgrade --quiet
check "v3 bookmark -> committed SYNC_FROM, file removed" "grep -q '^SYNC_FROM=[0-9a-f]' '$U3/.claude/ledger.conf' && [ ! -e '$U3/.claude/.ledger-sync' ]"
check "hand-set AUDIENCE_SURFACE preserved"    "grep -qx 'AUDIENCE_SURFACE=paper/main.tex' '$U3/.claude/ledger.conf'"
check "tree clean after --upgrade"             "[ -z \"\$(git -C '$U3' status --porcelain)\" ]"
check "second --upgrade is a no-op" "N=\$(git -C '$U3' rev-list --count HEAD); '$INSTALL' '$U3' --upgrade --quiet; [ \$(git -C '$U3' rev-list --count HEAD) -eq \$N ]"

U4="$(newrepo v4)"; installed "$U4"
rm -f "$U4/.claude/hooks/ledger-recall.sh"
python3 - "$U4/.claude/settings.json" <<'PYX'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d['hooks'].pop('UserPromptSubmit', None); json.dump(d, open(p, 'w'))
PYX
perl -pi -e 's/ledger-template-version: 6/ledger-template-version: 4/' "$U4/.claude/ledger.conf" "$U4"/.claude/hooks/* "$U4"/.githooks/*
git -C "$U4" add -A; commit "$U4" "x
Ledger: none — simulate a v4 install"
check "v4 repo: the digest offers the upgrade, naming recall" "digest '$U4' | grep -q 'LEDGER UPGRADE AVAILABLE.*prompt-time recall'"
"$INSTALL" "$U4" --upgrade --quiet
check "v4 -> v6: recall hook installed and registered" "[ -x '$U4/.claude/hooks/ledger-recall.sh' ] && grep -q 'ledger-recall.sh' '$U4/.claude/settings.json' && [ -z \"\$(git -C '$U4' status --porcelain)\" ]"

DL="$(newrepo dotted)"; installed "$DL"
python3 - "$DL/DECISIONS.md" <<'PYX'
import io, sys
p = sys.argv[1]; s = io.open(p).read()
s = s.replace('<!-- DECISIONS_LOG_START -->', '<!-- DECISIONS_LOG_START -->\n\n2026-01-01 · D-001 · an older decision · abc1234')
io.open(p, 'w').write(s)
PYX
git -C "$DL" add -A; commit "$DL" "x
Ledger: none — a log kept as dotted lines"
hc "$DL" -m "x" -m "Decision: the log keeps its own row style"
check "a dotted decisions log gets dotted rows" "grep -q '^20[0-9-]* · $(hid D 'the log keeps its own row style') · the log keeps its own row style · ' '$DL/DECISIONS.md' && ! grep -q '^| ' <(sed -n '/LOG_START/,/LOG_END/p' '$DL/DECISIONS.md')"

# ---------------------------------------------------------------------------
echo "13. dashboard, status and the index"
IDX="$LL_HOME_DIR/ledger"
CLAUDE_PROJECT_DIR="$D" "$D/.claude/hooks/ledger-rollup.sh"
DID="$(sed -n 's/^REPO_ID=//p' "$D/.claude/ledger.conf")"
check "block has a UTC _rebuilt stamp" "grep -qE '^_rebuilt [0-9-]+T[0-9:]+Z_' '$IDX/repos/$DID.md'"
check "block flags overdue + triage"   "grep -q 'overdue' '$IDX/repos/$DID.md' && grep -q 'triage' '$IDX/repos/$DID.md'"
P="$(newrepo pipeline)"; installed "$P"; hc "$P" -m "x" -m "Decision: the only decision here"
for i in 1 2 3; do ( cd "$P" && GIT_AUTHOR_NAME='github-actions[bot]' git commit -q --allow-empty -m "chore: bot $i" ); done
hc "$P" -m "chore: human work" -m "Ledger: none — pure housekeeping, nothing decided"
CLAUDE_PROJECT_DIR="$P" "$P/.claude/hooks/ledger-rollup.sh"
PID="$(sed -n 's/^REPO_ID=//p' "$P/.claude/ledger.conf")"
check "staleness ignores bot + sync commits" "grep -q '1 commit since last entry' '$IDX/repos/$PID.md'"
BEFORE="$(git -C "$D" status --porcelain)"
SOUT="$("$SKILL/bin/ledger-status.sh" --no-git 2>/dev/null)"
check "status prints the dashboard"      "printf '%s' \"\$SOUT\" | grep -q 'cross-repo dashboard'"
check "status never touches a repo"      "[ \"\$(git -C '$D' status --porcelain)\" = \"\$BEFORE\" ]"
check "--rebuild prunes orphan blocks"   "touch '$IDX/repos/ghost-999.md'; '$SKILL/bin/ledger-status.sh' --rebuild --no-git >/dev/null 2>&1; [ ! -f '$IDX/repos/ghost-999.md' ]"
# two machines share one index remote
BARE="$WORK/index.git"; git init -q --bare "$BARE"
git -C "$IDX" init -q 2>/dev/null; git -C "$IDX" add -A; git -C "$IDX" -c core.hooksPath="$NOHOOKS" commit -q -m seed
git -C "$IDX" remote add origin "$BARE"; git -C "$IDX" push -q -u origin main 2>/dev/null
M2="$WORK/machine2-index"; git clone -q "$BARE" "$M2"
PUSH="$SKILL/templates/hooks/ledger-index-push.sh"
printf '## machine-2 block\n_rebuilt 2030-01-01T00:00:00Z_\n' > "$M2/repos/$DID.md"
printf 'other-repo\t-\tLEDGER.md\t2026-01-01\n' >> "$M2/registry.tsv"
LEDGER_HOME="$M2" "$PUSH"
printf 'machine-1-repo\t-\tLEDGER.md\t2026-01-02\n' >> "$IDX/registry.tsv"   # this machine changed too
"$PUSH" > "$WORK/push.out"
check "second machine's push is not rejected" "[ \"\$(git -C '$IDX' rev-parse HEAD)\" = \"\$(git -C '$BARE' rev-parse main)\" ]"
check "registry rows from both machines kept"  "grep -q '^other-repo' '$IDX/registry.tsv' && grep -q '^machine-1-repo' '$IDX/registry.tsv'"
check "newest block stamp won"                 "grep -q 'machine-2 block' '$IDX/repos/$DID.md'"
git -C "$IDX" remote set-url origin "$WORK/nowhere.git"; printf 'offline-repo\t-\tLEDGER.md\t2026-01-03\n' >> "$IDX/registry.tsv"
OUT="$("$PUSH" --timeout 2)"
check "unreachable remote: one line, no failure" "[ \$(printf '%s' \"\$OUT\" | grep -c 'unpushed') -eq 1 ]"

# ---------------------------------------------------------------------------
echo "13b. entries arrive by date; Supersedes: … by …; dashboard does not churn"
O="$(newrepo order)"; installed "$O"
commit "$O" "feat: new

Decision: a decision made today"
GIT_AUTHOR_DATE="2020-05-05T10:00:00" git -C "$O" -c core.hooksPath="$NOHOOKS" commit -q --allow-empty -m "feat: old

Decision: a decision from long ago"
sync_ "$O"
check "an older entry lands below a newer one" "hdrs '$O' | head -1 | grep -q \"$(hid D 'a decision made today')\""
OLDD="$(hid D 'a decision from long ago')"; NEWD="$(hid D 'a decision made today')"
hc "$O" -m "tidy" -m "Supersedes: $OLDD by $NEWD
Tidy: one duplicate folded"
check "Supersedes: X by Y points at the survivor" "blk '$O' $OLDD | grep -q \"⤳ superseded by $NEWD\" && grep -q \"^## $NEWD · CLOSED\" '$O/LEDGER.md'"
check "a Tidy: trailer alone passes the gate" "ghas '^Tidy:' -C '$O' log --format=%B -2"
ID13="$(sed -n 's/^REPO_ID=//p' "$O/.claude/ledger.conf")"
CLAUDE_PROJECT_DIR="$O" "$O/.claude/hooks/ledger-rollup.sh"; M1="$(stat -f %m "$IDX/repos/$ID13.md" 2>/dev/null || stat -c %Y "$IDX/repos/$ID13.md")"
cp "$IDX/repos/$ID13.md" "$WORK/blk1"; CLAUDE_PROJECT_DIR="$O" "$O/.claude/hooks/ledger-rollup.sh"
check "unchanged block is not rewritten (only the stamp would move)" "cmp -s '$WORK/blk1' '$IDX/repos/$ID13.md'"
check "hash ids are never read as legacy ids" "python3 -c \"import sys; sys.path.insert(0,'$SKILL/templates/hooks'); from _ledger_parse import ID_RE; assert ID_RE.findall('Closes: F-020200f, D-014') == ['F-020200f','D-014'], ID_RE.findall('Closes: F-020200f, D-014')\""

# ---------------------------------------------------------------------------
echo "13c. tidy: due by volume of work and time, reset by a Tidy: commit"
T="$(newrepo tidy)"
GIT_AUTHOR_DATE="2026-01-01T10:00:00" GIT_COMMITTER_DATE="2026-01-01T10:00:00" installed "$T"
TS() { CLAUDE_PROJECT_DIR="$T" python3 "$T/.claude/hooks/_ledger_parse.py" tidy-status "$T/LEDGER.md" "$T"; }
for i in 1 2 3 4 5; do commit "$T" "f$i

Decision: small decision number $i"; done
sync_ "$T"
check "a little work: not due" "[ -z \"\$(TS)\" ]"
for i in $(seq 1 26); do commit "$T" "g$i

Finding: measured fact number $i about the thing"; done
sync_ "$T"
check "enough work over enough time: due, with the reason" "TS | grep -q 'new entries' && TS | grep -q 'never tidied'"
check "the digest offers /ledger-tidy" "digest '$T' | grep -q 'Tidy due:.*ledger-tidy'"
CLAUDE_PROJECT_DIR="$T" "$T/.claude/hooks/ledger-rollup.sh"
check "the dashboard flags it" "grep -q 'tidy due' \"$IDX/repos/\$(sed -n 's/^REPO_ID=//p' '$T/.claude/ledger.conf').md\""
hc "$T" -m "chore(ledger): tidy" -m "Tidy: nothing to fold"
check "a Tidy: commit resets it" "[ -z \"\$(TS)\" ]"
B2="$(newrepo burst)"; installed "$B2"
for i in $(seq 1 80); do commit "$B2" "b$i

Decision: burst decision number $i of many"; done
sync_ "$B2"
check "a one-day burst is due regardless of time" "CLAUDE_PROJECT_DIR='$B2' python3 '$B2/.claude/hooks/_ledger_parse.py' tidy-status '$B2/LEDGER.md' '$B2' | grep -q 'over 0 days'"
commit "$T" "x

Opens: the cache is invalidated on every deploy now
Decision: bust the cache on every deploy
Opens: C-021"
commit "$T" "y

Decision: bust the whole cache on every single deploy"
sync_ "$T"
REP="$(CLAUDE_PROJECT_DIR="$T" python3 "$T/.claude/hooks/_ledger_parse.py" tidy-report "$T/LEDGER.md" "$T")"
check "report: an open item opened with its decision" "printf '%s' \"\$REP\" | grep -q 'opened in the same commit as'"
check "report: near-duplicate decisions"             "printf '%s' \"\$REP\" | grep -q \"$(hid D 'bust the cache on every deploy') ≈\\|≈ $(hid D 'bust the cache on every deploy')\""
check "report: id-only junk"                         "printf '%s' \"\$REP\" | grep -A3 'Empty or id-only' | grep -q 'C-021'"

# ---------------------------------------------------------------------------
echo "13d. worktrees, merges, and ids of another register"
WT="$(newrepo wtmain)"; installed "$WT"
git -C "$WT" worktree add -q -b feat-wt "$WORK/wt-side" 2>/dev/null
( cd "$WORK/wt-side" && CLAUDE_PROJECT_DIR="$WT" git commit -q --allow-empty -m "x" -m "Decision: made in a worktree while the session points at main" ) >/dev/null 2>&1
check "a worktree commit syncs the WORKTREE's ledger" "grep -q 'made in a worktree' '$WORK/wt-side/LEDGER.md' && ! grep -q 'made in a worktree' '$WT/LEDGER.md'"
check "…and main's tree is untouched" "[ -z \"\$(git -C '$WT' status --porcelain)\" ]"
git -C "$WT" checkout -q -b side2; commit "$WT" "y

Decision: arrived on a branch whose hooks did not run"; git -C "$WT" checkout -q main
( cd "$WT" && git merge --no-ff --no-edit side2 ) > "$WORK/merge.out" 2>&1
check "post-merge says what the merge brought in" "grep -q 'this merge brought 1 ledger entry' '$WORK/merge.out' && [ -z \"\$(git -C '$WT' status --porcelain)\" ]"
hc "$WT" -m "chore: record merged ledger entries" -m "Ledger: none — recording entries a merge brought in"
check "…and the next commit records it" "grep -q 'arrived on a branch whose hooks' '$WT/LEDGER.md'"
X="$(newrepo extids)"
for i in 1 2 3; do commit "$X" "c$i

Refs: C-01$i"; done
installed "$X"
check "install detects another register's ids" "grep -qx 'EXTERNAL_IDS=C' '$X/.claude/ledger.conf'"
hc "$X" -m "fix" -m "Opens: C-032 -- the gain target disagrees with the simulator by 149x
Refs: C-022, C-026"
check "Opens: C-… <words> and Refs: C-… pass the gate" "grep -q '^C-032 -- the gain target disagrees' '$X/LEDGER.md'"
check "…and the other register's ids ride along as a pointer" "grep -q '^· Refs: C-022, C-026' '$X/LEDGER.md'"
hc "$X" -m "x" -m "Opens: C-021"
check "an id-only entry is still rejected" "grep -q 'starts with an id' '$WORK/err'"
sed -i.bak '/^EXTERNAL_IDS=/d' "$X/.claude/ledger.conf"; rm -f "$X/.claude/ledger.conf.bak"
hc "$X" -m "x" -m "Refs: C-022"
check "without EXTERNAL_IDS, an unknown id is rejected" "grep -q 'no entry C-022' '$WORK/err'"

# ---------------------------------------------------------------------------
echo "13e. duplicates are stopped at the gate; a tidy that leaves the list long is not re-nagged"
DU="$(newrepo dups)"; installed "$DU"
hc "$DU" -m "plan" -m "Decision: every declared input and every decision is a field of one DesignDecisions record that travels from design to results"
hc "$DU" -m "enact" -m "Decision: every declared input and every design decision is a field of one frozen DesignDecisions record that travels design to results"
check "a restated decision is rejected, naming the one it restates" "grep -q \"reads like $(hid D 'every declared input and every decision is a field of one DesignDecisions record that travels from design to results')\" '$WORK/err'"
hc "$DU" -m "enact" -m "Refs: $(hid D 'every declared input and every decision is a field of one DesignDecisions record that travels from design to results')"
check "…Refs: is the way to say it enacts it" "[ \$? -eq 0 ]"
hc "$DU" -m "refine" -m "Decision: every declared input and every design decision is a field of one frozen DesignDecisions record that travels design to results
Refs: $(hid D 'every declared input and every decision is a field of one DesignDecisions record that travels from design to results')"
check "…and a new entry that names it passes" "[ \$? -eq 0 ]"
hc "$DU" -m "decide: unrelated" -m "Decision: interview loop is two rounds with no take-home"
check "an unrelated decision is not blocked" "[ \$? -eq 0 ]"
CAP="$(newrepo cap)"; installed "$CAP"
for i in $(seq 1 25); do commit "$CAP" "o$i

Opens: overflow problem number $i needing attention"; done
sync_ "$CAP"
hc "$CAP" -m "chore(ledger): tidy" -m "Tidy: reviewed, all 25 are real"
check "right after a tidy, a long open list is not 'tidy due' again" "[ -z \"\$(CLAUDE_PROJECT_DIR='$CAP' python3 '$CAP/.claude/hooks/_ledger_parse.py' tidy-status '$CAP/LEDGER.md' '$CAP')\" ]"
MI="$(newrepo mirrors)"
printf '# Concerns\n\n## C-101 · the cache leaks\n- **Status.** Closed — fixed in the loader.\n\n## C-102 · the queue stalls\n- **Status.** Open.\n' > "$MI/CONCERNS.md"
git -C "$MI" add CONCERNS.md; commit "$MI" "docs: concerns"
printf 'EXTERNAL_IDS=C\n' > /dev/null; installed "$MI"
echo 'EXTERNAL_IDS=C' >> "$MI/.claude/ledger.conf"
commit "$MI" "x

Opens: C-101 -- the cache leaks memory on every reload
Opens: C-102 -- the queue stalls under back-pressure"
sync_ "$MI"
REP="$(CLAUDE_PROJECT_DIR="$MI" python3 "$MI/.claude/hooks/_ledger_parse.py" tidy-report "$MI/LEDGER.md" "$MI")"
check "report: a mirror whose concern is closed there → close here" "printf '%s' \"\$REP\" | grep 'C-101' | grep -q 'CLOSE here too'"
check "report: a mirror still open there → keep" "printf '%s' \"\$REP\" | grep 'C-102' | grep -q 'still open there'"

# ---------------------------------------------------------------------------
echo "13f. what this checkout has not shared — and what other machines have not"
export LEDGER_HOST=testhost            # this machine, as the index names it
SB="$WORK/share.git"; git init -q --bare "$SB"
SA="$(newrepo shareA)"; installed "$SA"; git -C "$SA" remote add origin "$SB"; git -C "$SA" push -q -u origin main 2>/dev/null
hc "$SA" -m "x" -m "Decision: a decision only this machine has"
SH() { CLAUDE_PROJECT_DIR="$1" python3 "$1/.claude/hooks/_ledger_parse.py" share-state "$1" "$LL_HOME_DIR/ledger" "${2:-testhost}" "$(sed -n 's/^REPO_ID=//p' "$1/.claude/ledger.conf")"; }
check "unpushed records are reported" "SH '$SA' | grep -q 'main holds 1 ledger record not pushed to origin/main'"
check "…and the digest says so"       "digest '$SA' | grep -q 'Not shared: main holds 1 ledger record not pushed'"
git -C "$SA" push -q 2>/dev/null
check "after the push: nothing"       "[ -z \"\$(SH '$SA')\" ]"
SB2="$WORK/shareB"; git clone -q "$SB" "$SB2"; "$INSTALL" "$SB2" --quiet >/dev/null 2>&1
hc "$SB2" -m "y" -m "Decision: made on the other machine"; git -C "$SB2" push -q 2>/dev/null; git -C "$SA" fetch -q
check "records on origin not pulled here (as of the last fetch)" "SH '$SA' | grep -q 'origin/main has 1 ledger record not pulled here (as of the last fetch'"
git -C "$SA" pull -q --no-rebase 2>/dev/null
git -C "$SA" checkout -q -b feature; hc "$SA" -m "z" -m "Decision: work on a side branch"; git -C "$SA" checkout -q main
git -C "$SA" worktree add -q "$WORK/shareA-wt" feature 2>/dev/null
check "a branch with its worktree is named"  "SH '$SA' | grep -q \"branch feature (worktree .*shareA-wt) holds 1 ledger record not in main\""
LEDGER_HOST=rigmac CLAUDE_PROJECT_DIR="$SA" "$SA/.claude/hooks/ledger-rollup.sh"
check "the rollup writes this machine's hosts file" "grep -q 'feature:1' '$LL_HOME_DIR/ledger/hosts/rigmac.tsv'"
check "the block says which machine rolled it up"  "grep -q ' on rigmac · ' \"$LL_HOME_DIR/ledger/repos/\$(sed -n 's/^REPO_ID=//p' '$SA/.claude/ledger.conf').md\""
check "another machine's session sees rigmac's unmerged work" "SH '$SA' laptop | grep -q 'on rigmac (as of .*unmerged branches feature:1'"
check "…its own host file is not echoed back"                 "! SH '$SA' rigmac | grep -q 'on rigmac'"
check "the dashboard lists it per machine" "'$SKILL/bin/ledger-status.sh' --no-git 2>/dev/null > '$WORK/dash.out'; sed -n '/Not shared yet/,/^## [^N]/p' '$WORK/dash.out' | grep -q 'rigmac'"
unset LEDGER_HOST

# ---------------------------------------------------------------------------
echo "13g. the Lore query side: context, generated rules, stale, validate, anti-patterns"
LQ="$(newrepo lore)"; installed "$LQ"
mkdir -p "$LQ/src"; echo a > "$LQ/src/auth.py"; git -C "$LQ" add -A
hc "$LQ" -m "feat: token refresh" -m "Decision: refresh expired tokens inline in the request interceptor
Constraint: the auth service does not support token introspection
Rejected: extend the token lifetime to a full day of validity | security policy violation
Directive: error handling is intentionally broad; do not narrow it without checking upstream
Confidence: low"
L1() { ( cd "$LQ" && .claude/hooks/ledger "$@" ); }
check "context <path> harvests directive, constraint, rejected" "L1 context src/auth.py > '$WORK/ctx'; grep -q 'intentionally broad' '$WORK/ctx' && grep -q 'token introspection' '$WORK/ctx' && grep -q 'full day of validity' '$WORK/ctx'"
check "…and the entries those commits made"    "grep -q \"$(hid D 'refresh expired tokens inline in the request interceptor')\" '$WORK/ctx'"
check "directives <path> shows only directives" "L1 directives src/auth.py | grep -q 'intentionally broad' && ! L1 directives src/auth.py | grep -q 'introspection'"
RF="$(ls "$LQ/.claude/rules/ledger/"*.md 2>/dev/null | head -1)"
check "post-commit generated a path-scoped rule"  "[ -n '$RF' ] && grep -q '\"src/auth.py\"' '$RF' && grep -q 'Directive:' '$RF'"
check "…in a gitignored directory"                "git -C '$LQ' check-ignore -q '$RF'"
hc "$LQ" -m "decide: no code" -m "Decision: the audit log is kept for two years
Directive: never shorten the retention without legal sign-off"
check "a record with no files makes no rule"      "[ \$(ls '$LQ/.claude/rules/ledger/' | wc -l) -eq 1 ]"
check "the digest tags a low-confidence decision" "digest '$LQ' | grep -q 'low confidence'"
hc "$LQ" -m "x" -m "Decision: extend the token lifetime to a full day of validity for everyone"
check "the gate stops re-adopting a rejected alternative" "grep -q 're-adopts what' '$WORK/err' && grep -q 'rejected' '$WORK/err'"
hc "$LQ" -m "x" -m "Retires: a nightly batch job is good enough for the export pipeline"
hc "$LQ" -m "x" -m "Decision: run a nightly batch job for the export pipeline, good enough for now"
check "the gate stops re-adopting a retired framing" "grep -q 'retired' '$WORK/err'"
hc "$LQ" -m "x" -m "Decision: run a nightly batch job for the export pipeline, good enough for now
Supersedes: $(hid R 'a nightly batch job is good enough for the export pipeline')"
check "…unless the commit supersedes it on purpose" "[ \$? -eq 0 ]"
for i in 1 2 3; do echo "$i" >> "$LQ/src/auth.py"; git -C "$LQ" add -A; hc "$LQ" -m "tweak $i" -m "Ledger: none — trivial change to the auth file"; done
check "stale: a directive whose file changed since" "L1 stale 3 | grep -q 'intentionally broad'"
git -C "$LQ" -c core.hooksPath="$NOHOOKS" commit -q --allow-empty -m "wip without a trailer"
check "validate finds history made without the hooks" "L1 validate 3 | grep -q '1 of the last 3 commits'"
hc "$LQ" -m "retire" -m "Decision: tokens are refreshed by a dedicated background service
Supersedes: $(hid D 'refresh expired tokens inline in the request interceptor')"
L1 rules >/dev/null
check "a superseded decision's rule is withdrawn" "[ -z \"\$(ls '$LQ/.claude/rules/ledger/' 2>/dev/null)\" ]"

# ---------------------------------------------------------------------------
echo "13h. ledger search"
SR="$(newrepo search)"; installed "$SR"
commit "$SR" "a

Decision: water-filling answers spike-rate allocation, not the neuron count
Retires: report the neuron count as a bracket between the knee and water-filling"
commit "$SR" "b

Decision: the decoder computes its gain in observation space
Supersedes: $(hid D 'water-filling answers spike-rate allocation, not the neuron count')"
commit "$SR" "c

Finding: the vendor API caps requests at ten per second"
sync_ "$SR"
S1() { ( cd "$SR" && .claude/hooks/ledger search "$@" ); }
check "search finds by topic, retired and superseded included" "S1 should we use water-filling for allocation > '$WORK/s1'; grep -q 'retired' '$WORK/s1' && grep -q 'SUPERSEDED by' '$WORK/s1'"
check "…ranked: the matching entries before unrelated ones" "! head -2 '$WORK/s1' | grep -q 'vendor API'"
check "an id in the words ranks first" "S1 $(hid F 'the vendor API caps requests at ten per second') | head -1 | grep -q 'vendor API'"
check "nothing relevant → says so" "S1 kubernetes helm chart | grep -q 'Nothing in the ledger matches'"

# ---------------------------------------------------------------------------
echo "13i. prompt-time recall, and its calibration at tidy"
RC="$(newrepo recall)"; installed "$RC"
F_OV="$(hid F 'the per-cell information-form update diverges when receptive fields overlap')"
D_AC="$(hid D 'the filter state lives on the acuity lattice, not on the receptor grid')"
commit "$RC" "a

Opens: the per-cell information-form update diverges when receptive fields overlap"
commit "$RC" "b

Decision: the filter state lives on the acuity lattice, not on the receptor grid"
commit "$RC" "c

Decision: the vendor API is polled every ten seconds"
commit "$RC" "d

Decision: the filter state stays on the receptor grid; the acuity lattice is the control arm
Supersedes: $D_AC"
commit "$RC" "e

Closes: $F_OV"
sync_ "$RC"
RH() {  # RH <session> <prompt> -> the hook's additionalContext ('' when silent)
  python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "prompt": sys.argv[2], "transcript_path": ""}))' "$1" "$2" 2>/dev/null \
    | ( cd "$RC" && "$RC/.claude/hooks/ledger-recall.sh" ) \
    | python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t.strip() else "")'
}
echo '{"session_id":"s1"}' | CLAUDE_PROJECT_DIR="$RC" "$RC/.claude/hooks/digest.sh" >/dev/null 2>&1
SEEN="$RC/.git/ledger-recall/seen-s1.txt"
check "settings.json registers the recall hook" "python3 -c 'import json;d=json.load(open(\"$RC/.claude/settings.json\"));assert \"ledger-recall.sh\" in json.dumps(d[\"hooks\"][\"UserPromptSubmit\"])'"
check "the digest records what it showed, for this session" "grep -q '$(hid D 'the vendor API is polled every ten seconds')' '$SEEN' && ! grep -q '$F_OV' '$SEEN'"
RH s1 "why does the update diverge when the receptive fields overlap this much?" > "$WORK/r1"
check "a question on something the digest left out recalls it" "grep -q '$F_OV' '$WORK/r1' && grep -q 'Ledger recall' '$WORK/r1'"
check "…once per session"                 "[ -z \"\$(RH s1 'why does the update diverge when the receptive fields overlap this much?')\" ]"
check "…and again in another session"     "RH s2 'why does the update diverge when the receptive fields overlap this much?' | grep -q '$F_OV'"
check "an id the message names is resolved, with what replaced it" "RH s3 'what happened to $D_AC?' | grep -q 'SUPERSEDED by'"
check "small talk stays silent"           "[ -z \"\$(RH s4 'ok that sounds good, please run it again now')\" ]"
check "slash commands are left alone"     "[ -z \"\$(RH s5 '/ledger-tidy the receptive fields overlap and the update diverges')\" ]"
check "unrelated questions stay silent"   "[ -z \"\$(RH s6 'how do I configure the kubernetes helm chart for staging?')\" ]"
check "headless runs: silent"             "[ -z \"\$(CLAUDE_CODE_ENTRYPOINT=sdk-cli RH s7 'why does the update diverge when the receptive fields overlap this much?')\" ]"
printf 'RECALL=off\n' >> "$RC/.claude/ledger.conf"
check "RECALL=off: silent"                "[ -z \"\$(RH s8 'why does the update diverge when the receptive fields overlap this much?')\" ]"
sed -i.bak '/^RECALL=off$/d' "$RC/.claude/ledger.conf"; rm -f "$RC/.claude/ledger.conf.bak"
check "every prompt and recall is logged in the git dir, not the repo" "grep -q '	prompt	' '$RC/.git/ledger-recall/log.tsv' && grep -q '	shown	' '$RC/.git/ledger-recall/log.tsv' && ! git -C '$RC' status --porcelain | grep -q recall"

# calibration: a synthetic transcript, where the agent cites some of what was recalled
CAL() {  # CAL <repo> <n shown> <score> <n cited> <n near> <n near cited>
  python3 - "$@" <<'PYC'
import datetime, json, os, sys
repo, n, score, cited, nn, nc = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
d = os.path.join(repo, '.git', 'ledger-recall'); os.makedirs(d, exist_ok=True)
tr = os.path.join(d, 'transcript.jsonl')
t0 = datetime.datetime.now().timestamp() - 50000
iso = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
log, recs = [], []
for i in range(max(n, nn)):
    t = t0 + i * 600
    log.append(f"{t}\ts\t{tr}\tprompt\t2.0\t")
    said = []
    if i < n:
        log.append(f"{t}\ts\t{tr}\tshown\t{score}\tF-{i:07x}"); said += [f"F-{i:07x}"] if i < cited else []
    if i < nn:
        log.append(f"{t}\ts\t{tr}\tnear\t1.8\tD-{i:07x}"); said += [f"D-{i:07x}"] if i < nc else []
    recs.append({"type": "user", "timestamp": iso(t + 1), "message": {"role": "user", "content": f"question {i}"}})
    recs.append({"type": "assistant", "timestamp": iso(t + 5), "message": {"content": [{"type": "text", "text": "answer " + " ".join(said)}]}})
open(os.path.join(d, 'log.tsv'), 'w').write("\n".join(log) + "\n")
open(tr, 'w').write("\n".join(json.dumps(r) for r in recs) + "\n")
PYC
  ( cd "$1" && .claude/hooks/ledger recall-stats )
}
CR="$(newrepo calib)"; installed "$CR"
check "too few recalls: keep, and say how many more are needed" "CAL '$CR' 10 2.1 2 0 0 | grep -q 'needs 30.*10 so far'"
check "the weakest recalls go unused: raise the threshold" "CAL '$CR' 40 2.1 5 0 0 | grep -q 'set RECALL_MIN=2.25'"
check "held-back entries get looked up anyway: lower it" "CAL '$CR' 40 3.0 30 10 5 | grep -q 'set RECALL_MIN=1.75'"
check "used and nothing missed: keep"     "CAL '$CR' 40 3.0 30 10 0 | grep -q 'keep 2'"
check "the tidy report carries the calibration" "( cd '$CR' && .claude/hooks/ledger tidy ) | grep -q 'Recall threshold'"
printf 'RECALL_MIN=2.25\n' >> "$CR/.claude/ledger.conf"; git -C "$CR" add -A; commit "$CR" "chore(ledger): tidy
Decision: recall threshold 2.0 -> 2.25
Tidy: recall calibrated"
check "a committed change restarts the count" "( cd '$CR' && .claude/hooks/ledger recall-stats ) | grep -q '0 so far'"

# ---------------------------------------------------------------------------
echo "13j. a checkout that lost the executable bit, or has CRLF (a repo committed from Windows)"
WX="$(newrepo winexec)"; installed "$WX"
check "settings.json runs every hook through bash" "python3 -c 'import json,sys; d=json.load(open(\"$WX/.claude/settings.json\")); cs=[h[\"command\"] for bs in d[\"hooks\"].values() for b in bs for h in b[\"hooks\"]]; sys.exit(0 if cs and all(\"bash \\\"\$D/.claude/hooks/\" in c for c in cs) else 1)'"
chmod -x "$WX"/.claude/hooks/* "$WX"/.githooks/*
hc "$WX" -m "wip"
check "no exec bit: the commit gate still refuses a commit with no trailer" "grep -q 'REJECTED' '$WORK/err'"
hc "$WX" -m "feat: x" -m "Decision: the gate runs even when the hooks lost their executable bit"
check "no exec bit: the post-commit sync still records and commits" "ghas 'the gate runs even when' -C '$WX' show HEAD -- LEDGER.md && ghas 'chore: ledger sync' -C '$WX' log -1 --format=%s"
check "no exec bit: the recall hook runs from its settings command" "echo '{\"session_id\":\"x\",\"prompt\":\"does the gate run when hooks lost the executable bit?\"}' | CLAUDE_PROJECT_DIR='$WX' sh -c 'D=\"\${CLAUDE_PROJECT_DIR:-.}\"; bash \"\$D/.claude/hooks/ledger-recall.sh\"' 2>'$WORK/rerr' | grep -q UserPromptSubmit; [ ! -s '$WORK/rerr' ]"
printf '#!/bin/sh\n# living-ledger shim: runs the repo committed .githooks/commit-msg.\nT="$(git rev-parse --show-toplevel)/.githooks/commit-msg"\n[ -x "$T" ] && exec "$T" "$@"\nexit 0\n' > "$WX/.git/hooks/commit-msg"
digest "$WX" >/dev/null
check "an older shim is rewritten in place at the next session, not kept as .pre-ledger" "grep -q 'living-ledger shim v2' '$WX/.git/hooks/commit-msg' && [ ! -e '$WX/.git/hooks/commit-msg.pre-ledger' ]"
OLDSET='{"hooks":{"SessionStart":[{"matcher":"startup|resume|clear","hooks":[{"type":"command","command":"sh -c '"'"'D=\"${CLAUDE_PROJECT_DIR:-.}\"; \"$D/.claude/hooks/digest.sh\"'"'"'","timeout":20}]}]}}'
printf '%s\n' "$OLDSET" > "$WX/.claude/settings.json"; "$INSTALL" "$WX" --quiet
check "an install rewrites hook commands that ran scripts directly" "python3 -c 'import json,sys; d=json.load(open(\"$WX/.claude/settings.json\")); cs=[h[\"command\"] for bs in d[\"hooks\"].values() for b in bs for h in b[\"hooks\"]]; sys.exit(0 if all(\"bash \\\"\$D/.claude/hooks/\" in c for c in cs) and sum(\"digest.sh\" in c for c in cs) == 2 else 1)'"

FM="$(newrepo filemode)"; git -C "$FM" config core.fileMode false
"$INSTALL" "$FM" --quiet; git -C "$FM" add -A; commit "$FM" "chore: install
Ledger: none — installing the ledger tooling"
check "git ignoring exec bits (Windows): a fresh install still commits its scripts as 100755" "[ -z \"\$(git -C '$FM' ls-tree -r HEAD -- .claude/hooks .githooks | grep -v '_ledger_' | grep -v '^100755')\" ]"
git -C "$FM" rm -q --cached .claude/hooks/ledger-recall.sh; rm -f "$FM/.claude/hooks/ledger-recall.sh"
perl -pi -e 's/ledger-template-version: 6/ledger-template-version: 5/' "$FM/.claude/ledger.conf" "$FM"/.claude/hooks/* "$FM"/.githooks/*
git -C "$FM" add -A; commit "$FM" "x
Ledger: none — simulate a v5 install"
printf 'mine\n' > "$FM/user.txt"; git -C "$FM" add user.txt
"$INSTALL" "$FM" --upgrade --quiet
check "…and an upgrade there commits a new script as 100755" "git -C '$FM' ls-tree HEAD .claude/hooks/ledger-recall.sh | grep -q '^100755'"
check "…without committing what the user had staged" "! git -C '$FM' show --name-only --format= HEAD | grep -qx user.txt && git -C '$FM' diff --cached --name-only | grep -qx user.txt"

CR="$(newrepo crlf)"; installed "$CR"
hc "$CR" -m "feat: a" -m "Decision: the vendor API is polled every ten seconds"
python3 -c "import sys; p=sys.argv[1]; d=open(p,'rb').read().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'); open(p,'wb').write(d)" "$CR/LEDGER.md"
git -C "$CR" add LEDGER.md; commit "$CR" "x
Ledger: none — simulate a ledger written with CRLF line endings"
hc "$CR" -m "feat: b" -m "Decision: exports are written as parquet files"
check "a CRLF ledger is written back with LF, entries intact" "! grep -q \$'\\r' '$CR/LEDGER.md' && grep -q 'polled every ten seconds' '$CR/LEDGER.md' && grep -q 'written as parquet files' '$CR/LEDGER.md'"

# ---------------------------------------------------------------------------
echo "14. the user-level session hook"
SESS="$SKILL/bin/ledger-session.sh"
NL="$(newrepo noledger)"
O1="$(echo "{\"cwd\":\"$NL\"}" | "$SESS")"; O2="$(echo "{\"cwd\":\"$NL\"}" | "$SESS")"
check "no ledger: nudge once"  "printf '%s' \"\$O1\" | grep -q 'ledger-init' && [ -z \"\$O2\" ]"
check "v1 ledger: upgrade flag" "mkdir -p '$WORK/v1b/.claude'; git -C '$WORK/v1b' init -q; printf '<!-- ENTRIES_START -->\n' > '$WORK/v1b/LEDGER.md'; printf '# ledger-template-version: 1\nLEDGER_PATH=LEDGER.md\n' > '$WORK/v1b/.claude/ledger.conf'; echo '{\"cwd\":\"$WORK/v1b\"}' | '$SESS' | grep -q 'LEDGER UPGRADE AVAILABLE'"
check "current repo: silent"         "[ -z \"\$(echo '{\"cwd\":\"$D\"}' | '$SESS')\" ]"
check "headless: silent"        "[ -z \"\$(echo '{\"cwd\":\"$WORK/v1b\"}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli '$SESS')\" ]"

# ---------------------------------------------------------------------------
echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
