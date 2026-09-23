#!/usr/bin/env bash
# living-ledger in 60 seconds, in a throwaway repo (nothing outside it is touched).
#   bash demo/demo.sh          — or record it:  vhs demo/demo.tape  (brew install vhs)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$(cd "$(mktemp -d)" && pwd -P)"; export HOME="$D"   # paths show as ~/app, not a temp path
export LL_HOME_DIR="$D/claude" LL_SKILL_DIR="$HERE" LL_NO_GLOBAL_HOOK=1
export GIT_CONFIG_GLOBAL="$D/gitconfig"; git config --global user.name demo
git config --global user.email demo@example.com; git config --global init.defaultBranch main
step() { printf '\n\033[1;36m$ %s\033[0m\n' "$*"; sleep 1; }
cd "$D" && git init -q app && cd app && echo '# app' > README.md && git add . \
  && git commit -qm init --no-verify
"$HERE/install.sh" . --quiet && git add -A && git commit -qm "chore: install the living ledger" \
  -m "Decision: this repo keeps a living ledger" >/dev/null

step 'git commit -m "feat: encoder queue"          # no trailer'
mkdir -p src && echo 'q = []' > src/encoder.py && git add src
git commit -qm "feat: encoder queue"
sleep 2

step 'git commit -m "feat: encoder queue" -m "Decision: … / Rejected: … / Opens: … / Due: …"'
git commit -qm "feat: encoder queue" -m "Profiling showed 70% of encoder time waiting on the lock." \
  -m "Decision: use a single-writer queue for the encoder instead of a lock
Rejected: fine-grained locks | deadlocked under the stress test
Opens: the queue has no back-pressure yet
Due: 2026-12-01"
sleep 1

step 'sed -n "/ENTRIES_START/,\$p" LEDGER.md'
sed -n '/ENTRIES_START/,$p' LEDGER.md | sed '1,2d'
sleep 2

step '# … the next Claude Code session starts with:'
.claude/hooks/digest.sh | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' | sed -n '1,12p'
sleep 3
rm -rf "$D"
