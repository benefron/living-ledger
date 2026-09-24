# Changelog

Template versions are stamped into every installed file (`ledger-template-version: N`); a repo
running an older template is flagged at session start with `LEDGER UPGRADE AVAILABLE`, and
`/ledger-init --upgrade` (or `install.sh <repo> --upgrade`) upgrades it in one commit without
rewriting or renumbering any entry.

## Unreleased

- `ledger search <words>`: BM25 over every entry, live or dead, with its status and what
  replaced it; an id named in the query ranks first.

## v4 — 2026-09-23

From an audit of six repositories that ran v1–v3.

**Ids and sync**
- Entry ids are content hashes (`D-3fa9c1e`) — no more collisions between branches, worktrees,
  machines or cloud sessions, no renumbering on squash. Legacy sequential ids keep working.
- The ledger is derived from `git log` since a committed `SYNC_FROM` floor on every run; the
  per-machine bookmark is gone. An upgrade migrates the old bookmark into the floor.
- `ledger-merge.py` (`merge=ledger`): entry-wise merge of `LEDGER.md` and the `DECISIONS.md` log;
  3-way merge of the prose; the union of body lines when both sides touched an entry.
- New entries are newest-first within a batch, too.

**Vocabulary**
- `Finding:` now records a settled fact (STANDING). `Opens:` is the open problem/question.
  New: `Fixed:` (found and fixed here), `Action:` (`A-…`, a to-do), `Supersedes:`.
- Modifiers `Due:`, `Owner:`, `Area:`, `Pin:`, `Date:`; they and Lore trailers bind to the entry
  trailer directly above them instead of being copied onto every entry of the commit.
- `Closes:` / `Supersedes:` / `Refs:` leave the applying sha on the entry and are applied once — a
  hand re-open survives re-scans.

**The gate**
- `commit-msg` uses the sync's own trailer reader (python), so they can never disagree: a wrapped
  trailer is accepted *and* recorded; a ledger line outside the last paragraph, an unknown id,
  an id where words belong (`Finding: F-1 …`), or a malformed date is rejected with the reason.
- Exempt: `[bot]` authors, `LEDGER_SKIP=1`, `EXEMPT_SUBJECTS` / `EXEMPT_AUTHORS` (automation
  subjects are detected at install). The `chore: ledger sync` subject is no longer a loophole.

**Hooks and safety**
- Git hooks are activated as per-clone shims in `.git/hooks/` that keep existing hooks running;
  `core.hooksPath` (which silently disabled Git LFS) is no longer used, and v3's is migrated.
- post-commit skips a gitignored `DECISIONS.md` instead of failing and leaving the ledger staged;
  paths with spaces work; a failed auto-commit unstages what it staged.
- Reading never writes: the digest, the dashboard and `/ledger-status` derive into temp copies.
- Headless sessions (`claude -p`, SDK scripts) get no digest and run no sync.
- The installer un-ignores the ledger files if needed and warns when the remote is public.
- A user-level session hook nudges once in repos without a ledger and flags v0–v2 repos.

**Digest and dashboard**
- Overdue items first, then open items in the area being worked on; a Pinned (in-force) section;
  "recent" is the newest entries, not a 14-day window that empties after a break; more retired
  framings shown; `lint` reports malformed/duplicate headers; stale-rule check no longer flags
  rules that cite in-force decisions.
- Dashboard: `⏰ overdue` and `⚠ triage` flags; the lapse counter ignores bots, sync commits and
  exempt subjects; UTC stamps; the index push pulls (rebase) first and merges blocks by newest
  stamp, so two machines never reject each other.

**Tidy**
- `/ledger-tidy`: a report of what to review (open items that read as settled, overdue and aging
  items, near-duplicates and contradictions, empty entries, long pins, decisions without written
  reasoning, stale rules, competing registers), user-approved fixes, one commit with a `Tidy:`
  trailer. Nothing is deleted.
- "Tidy due" in the digest and `🧹 tidy due` on the dashboard when the volume of work since the
  last tidy (entries + 3 x merges + commits / 5) passes `TIDY_VOLUME` over `TIDY_MIN_DAYS`, or
  three times it in any span.
- `Supersedes: <old> by <new>` folds a duplicate into its survivor.
- The report shows each open item that mirrors another register's item (`EXTERNAL_IDS`) beside
  that register's own status, and proposes closing it only when every item it cites is closed.
- The gate rejects a new entry that reads like a live one (same similarity test as the report)
  unless the commit `Refs:`/`Supersedes:` it — duplicates are stopped where they are born. A
  `Tidy:` commit is exempt. An open list over the digest cap no longer re-triggers "tidy due"
  the day after a tidy that reviewed it.

**From the cloud review of v3** (`44eeae6`, never merged): new entries are inserted by date, so
late arrivals (a merge, a recovery) keep the file newest-first; an unchanged dashboard block is
not rewritten just to move its timestamp; hash ids are never read as legacy ids (tested).
`LL_SYNC_FROM` previews a recovery of dropped trailers without touching anything.

**Worktrees, merges, other registers**
- Hooks now find the right checkout in a git worktree. git exports `GIT_DIR` to hooks there,
  which made the repo-root lookup answer `.claude/hooks`, and `$CLAUDE_PROJECT_DIR` (preferred
  before) names the main checkout: every worktree commit was a silent no-op for the ledger, in
  every earlier version.
- `post-merge` reports entries a merge brought in (it cannot commit: git still holds the merge
  state); the next commit records them.
- `EXTERNAL_IDS=C`: id prefixes of another register the repo keeps (a `CONCERNS.md` numbered
  `C-001`…). The gate accepts `Refs: C-022` and `Opens: C-032 -- <words>`; the sync keeps them as a
  `· Refs:` pointer. Detected at install from the trailers already in history.

**Branches, worktrees, machines**
- `share-state`: ledger records this checkout has not shared or seen — unpushed, on the upstream
  but not pulled (last fetch, no network), on other local branches/worktrees, and unpushed on
  other machines. Shown in the digest ("Not shared: …"), the dashboard (`⇡`/`⇣`/`unmerged:` and
  `on <host>`), and as preconditions on "Tidy due".
- Each machine writes `hosts/<machine>.tsv` into the private index (single writer, no merge
  conflicts); `/ledger-status` lists every machine's unshared records.

**The Lore query side** (arXiv:2603.15566), put to work
- `.claude/hooks/ledger`: `context|directives|constraints|rejected <path>`, `open`, `decisions`,
  `retired`, `stale`, `validate`, `rules`, `tidy`, `share` — for any agent or person.
- Each commit's `Directive:`/`Constraint:`/`Rejected:` becomes a Claude Code path-scoped rule in
  `.claude/rules/ledger/` (gitignored, regenerated at session start and after each commit);
  a superseded decision's rule is withdrawn.
- The gate refuses a `Decision:` that re-adopts a rejected alternative or a retired framing
  unless the commit supersedes it; `Confidence: low` / `Reversibility: irreversible` are tagged in
  the digest; the tidy report lists stale directives and old low-confidence decisions.
- `templates/AGENTS.snippet.md` for other agents; `reference/lore-paper.md` compares point by point.

**Docs and packaging**
- The README leads with the workflow you actually see — Claude proposes one-line records and
  writes them into its commits; you approve — and keeps the vocabulary and internals as reference.
  The installer and `/ledger-init` say the same in two lines instead of reciting the vocabulary.
- CI badge, platform note, updating steps, `CONTRIBUTING.md`, a bug-report template, and
  `demo/` (a scripted walkthrough, and a `vhs` tape that records it).

**Upgrade** commits with `Ledger: none` (a template bump is not a project decision) and derives
pending trailers into the same single commit.

## v3 — 2026-09-22
Enforcement: committed `.githooks/commit-msg` (trailer required) and `post-commit` (sync and
auto-commit the ledger); `Refs:` backlinks; the level-2 `DECISIONS.md`; stale-rule detection;
automatic cross-repo index push; template version stamps and the upgrade flag.

## v2 — 2026-09-09
A global skill: the sync bookmark moved out of `LEDGER.md` into a gitignored file; the cross-repo
index and dashboard; `/ledger-status`, `/ledger-note`, `/ledger-setup`.

## v1 — 2026-08-27
A per-repo `LEDGER.md` synced from commit trailers at session start, with a bounded digest.
