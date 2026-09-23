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
digest() { CLAUDE_PROJECT_DIR="$1" "$1/.claude/hooks/digest.sh" 2>/dev/null | python3 -c \
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
check "every stamp is v4" "! grep -rl 'ledger-template-version: [0-35-9]' '$R/.claude' '$R/.githooks' >/dev/null"
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
echo "12. upgrades: v1 marker and v3 bookmark -> v4, nothing lost"
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
perl -pi -e 's/ledger-template-version: 4/ledger-template-version: 3/' "$U3/.claude/ledger.conf" "$U3"/.claude/hooks/*
git -C "$U3" add -A; commit "$U3" "x
Ledger: none — simulate a v3 install"
"$INSTALL" "$U3" --upgrade --quiet
check "v3 bookmark -> committed SYNC_FROM, file removed" "grep -q '^SYNC_FROM=[0-9a-f]' '$U3/.claude/ledger.conf' && [ ! -e '$U3/.claude/.ledger-sync' ]"
check "hand-set AUDIENCE_SURFACE preserved"    "grep -qx 'AUDIENCE_SURFACE=paper/main.tex' '$U3/.claude/ledger.conf'"
check "tree clean after --upgrade"             "[ -z \"\$(git -C '$U3' status --porcelain)\" ]"
check "second --upgrade is a no-op" "N=\$(git -C '$U3' rev-list --count HEAD); '$INSTALL' '$U3' --upgrade --quiet; [ \$(git -C '$U3' rev-list --count HEAD) -eq \$N ]"

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
echo "14. the user-level session hook"
SESS="$SKILL/bin/ledger-session.sh"
NL="$(newrepo noledger)"
O1="$(echo "{\"cwd\":\"$NL\"}" | "$SESS")"; O2="$(echo "{\"cwd\":\"$NL\"}" | "$SESS")"
check "no ledger: nudge once"  "printf '%s' \"\$O1\" | grep -q 'ledger-init' && [ -z \"\$O2\" ]"
check "v1 ledger: upgrade flag" "mkdir -p '$WORK/v1b/.claude'; git -C '$WORK/v1b' init -q; printf '<!-- ENTRIES_START -->\n' > '$WORK/v1b/LEDGER.md'; printf '# ledger-template-version: 1\nLEDGER_PATH=LEDGER.md\n' > '$WORK/v1b/.claude/ledger.conf'; echo '{\"cwd\":\"$WORK/v1b\"}' | '$SESS' | grep -q 'LEDGER UPGRADE AVAILABLE'"
check "v4 repo: silent"         "[ -z \"\$(echo '{\"cwd\":\"$D\"}' | '$SESS')\" ]"
check "headless: silent"        "[ -z \"\$(echo '{\"cwd\":\"$WORK/v1b\"}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli '$SESS')\" ]"

# ---------------------------------------------------------------------------
echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
