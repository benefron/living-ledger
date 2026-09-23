---
description: One-time per machine — back your cross-repo ledger index with your own private git repo
argument-hint: "[git-remote-url]"
---

# /ledger-setup

`~/.claude/ledger/` is **your** cross-repo index: a registry of your ledgers, one dashboard block
per repo, and `DASHBOARD.md`. Backing it with a private git repo lets the dashboard follow you
across machines. It is separate from the living-ledger tool itself and is never shared.
Argument: `$ARGUMENTS` (the remote URL, if you have it).

## Before anything — tell the user, plainly

> The index holds your open findings, decisions and file references from every repo, and it is
> pushed automatically at session start/end. The repo **must be private**. Please create it
> yourself, e.g.:
>
> ```bash
> gh repo create ledger-index --private --description "my living-ledger cross-repo index"
> ```
>
> Then give me the URL, or run `/ledger-setup <url>`.

Wait for the URL and the confirmation that it is private. Declining is fine: everything keeps
working locally, just without cross-machine sync.

## Steps

1. `~/.claude/skills/living-ledger/install.sh --global-only` (creates the directory, the
   commands, the merge-driver attributes, and the user-level session hook).
2. **First machine** (`~/.claude/ledger` has no commits yet):
   ```bash
   git -C ~/.claude/ledger init -b main
   git -C ~/.claude/ledger remote add origin <url>
   git -C ~/.claude/ledger add -A
   git -C ~/.claude/ledger commit -m "chore: seed living-ledger index"
   git -C ~/.claude/ledger push -u origin main
   ```
   **Another machine** (the remote already has content):
   ```bash
   mv ~/.claude/ledger ~/.claude/ledger.bak
   git clone <url> ~/.claude/ledger
   cp -n ~/.claude/ledger.bak/.local/* ~/.claude/ledger/.local/ 2>/dev/null || true
   ~/.claude/skills/living-ledger/install.sh --global-only
   ```
3. Run `/ledger-status --rebuild` to populate and push.

Two machines never block each other: pushes pull with rebase first, a repo's block and
`DASHBOARD.md` merge by newest `_rebuilt` stamp (`merge=ledger-block`, registered by the step-1
installer), and `registry.tsv` merges by union.
