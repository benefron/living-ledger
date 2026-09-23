---
description: Cross-repo view of what is open, overdue and recently decided across all registered ledgers
argument-hint: "[--rebuild] [--no-git] [repo-id ...]"
---

# /ledger-status

One combined view of every repo that has a living ledger on this machine.

```bash
~/.claude/skills/living-ledger/bin/ledger-status.sh $ARGUMENTS
```

The script pulls the shared index (if `~/.claude/ledger/` has a remote), rebuilds each registered
repo's block from its ledger **plus any trailers its history holds that the committed ledger has
not caught up with** — computed in a temp copy, so no repo's working tree is ever touched —
regenerates `~/.claude/ledger/DASHBOARD.md`, commits and pushes the index (`--no-git` stays
local), and prints the dashboard. `--rebuild` also prunes blocks whose repo left the registry.
Trailing names filter to those repo ids.

## Report to the user, per repo

- overdue items first (`⏰`), then the open items;
- the most recent decisions;
- **Not shared yet — per machine** (top of the dashboard): records unpushed on a machine,
  branches or worktrees holding records not merged, a ledger edited but not committed — each
  machine's own report, with the time it was made. Say which machine to go to, and what to push
  or merge there;
- the header line names the machine that last rebuilt the block (`on <host>`), with `⇡ N records
  unpushed`, `⇣ N records not pulled` and `unmerged: <branch> (N)` for that machine;
- the flags on the header line: `N commits since last entry` (capture is lapsing — bots, the
  ledger's own sync commits and `EXEMPT_SUBJECTS` are not counted), `⚠ triage` (more open items
  than the session digest can show), `🧹 tidy due` (enough work and time since the last tidy —
  suggest `/ledger-tidy` there), `ledger uncommitted` (a hand edit waiting to be committed),
  `template vN` in the "behind" section (run `/ledger-init --upgrade` there).

Repos printed to stderr as `gone:` are registered on another machine or deleted — mention them,
don't act.
