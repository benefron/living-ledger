# Project Ledger — decisions, findings, retired framings

**This is the single register.** If you want to know what was decided, what is open, or what has
already been settled and must not be re-litigated, it is here. Newest first.

**Read this before proposing anything that sounds new.** A large fraction of the entries below are
questions that were already asked and answered — sometimes answered wrongly first, then corrected.
Re-opening one costs more than reading it.

This file is an instance of the **Lore** pattern (git commit messages as a structured knowledge
protocol for AI coding agents — arXiv:2603.15566). The commit trailer is the atomic unit of
institutional knowledge; this file is the pre-digested read surface over those trailers.

---

## How to use this file

**Finding things.** Grep it. Every entry is one greppable block; the terms you would naturally
search for appear in the entry bodies deliberately.

```bash
grep -A4 '^## F-'       LEDGER.md   # all findings
grep -A4 '· OPEN ·'     LEDGER.md   # everything still open
grep -A4 '· retired ·'  LEDGER.md   # do not re-propose these
grep -B1 -A4 '<topic>'  LEDGER.md   # everything about one topic
```

**Three levels of a decision.** A decision is captured at up to three levels, each for a different
reader, and the levels must agree:

| Level | Where | Reader | What it holds |
|---|---|---|---|
| 1. Fact | **this file**, via the `Decision:` trailer of the commit that enacted it | future sessions, the injected digest | one sentence, status, evidence pointer |
| 2. Reasoning | the **body of the commit** that carried the trailer, and **`DECISIONS.md`** when it needs more room — append-only, every section dated | you, collaborators | what was decided (quoting level 1), why — the numbers and the `F-`/`D-` ids, what was rejected and why, where it lives, what validation is still pending |
| 3. Audience | *only if this repo has an audience surface* — a deck script, a paper, the README's claims. `.claude/ledger.conf` names it under `AUDIENCE_SURFACE=` | that audience | the current state. Updated **on request**; nothing rebuilds it automatically, and it never rewrites history |

The order is fixed: the trailer goes on the commit → the post-commit hook writes level 1 → `ledger-sync.sh`
appends the dated fact to level 2's log → a human writes the reasoning above it. Level 3 moves only when
you ask for it.

A decision that exists at level 1 only is a verdict with no argument behind it. A decision that exists at
level 2 only is invisible to every future session. Both are incomplete.

**Level 2 is append-only and keeps its history.** A superseded decision is never deleted and never
edited: it gains a `**Superseded by:** <section / ledger id> · <date>` line, and the section that
replaces it opens with `**Supersedes:** …`. The corrections *are* the record.

**Entry format.** The header line is machine-parsed — keep it exact.

```
## <ID> · <STATUS> · <type> · <area|-> · <date>
<one or two lines of what and why>
→ <file:line evidence> · <pointer or closes-with>
```

| Field | Values |
|---|---|
| `ID` | `D-` decision · `F-` finding · `A-` action · `R-` retired framing · `N-` note/thought, then 7 hex: a content hash of the entry text (`F-3fa9c1e`), so the same entry gets the same id on every clone and branch — never a counter. Older sequential ids (`F-014`) stay valid and are never renumbered. |
| `STATUS` | `OPEN` (something to resolve) · `CLOSED` (resolved; for a decision: settled and in force) · `SUPERSEDED` (replaced — see its `⤳` line) · `STANDING` (a settled fact, a retired framing, a note) |
| `type` | `decision` · `finding` · `action` · `retired` · `note` · `thought` |
| `area` | a short workstream / component tag, or `-` if it belongs to none |
| `date` | `YYYY-MM-DD`, optionally suffixed `(recorded)`, `(from <sha>)` or `(backfilled)` |

**Date honesty.** A date is only ever one of:
- **bare** — the entry was written on that date, live.
- **`(recorded)`** — transcribed from a doc that already carried that date.
- **`(from <sha>)`** — recovered via `git log -S`, i.e. the commit that introduced the claim.
- **`(backfilled)`** — reconstructed with no better evidence; treat the date as approximate.

Never write an undecorated date onto a backfilled entry. Inventing a tidy history is the exact
failure this file exists to prevent.

**Nothing is ever deleted.** Status changes; git holds the history.

---

## How entries get here

Three capture paths, all cheap:

1. **Commit trailers.** Every commit carries one (the `commit-msg` gate checks);
   `.claude/hooks/ledger-sync.sh` reads `git log` and records any it has not seen. Vocabulary:
   ```
   Decision:   <one line>              a settled choice               -> D-…, CLOSED (in force)
   Finding:    <one line>              a settled fact / result        -> F-…, STANDING
   Opens:      <one line>              an open problem or question    -> F-…, OPEN
   Fixed:      <one line>              found and resolved right here  -> F-…, CLOSED
   Action:     <one line>              a to-do                        -> A-…, OPEN
   Closes:     F-3fa9c1e               resolves an open entry
   Retires:    <the framing>           an approach that is now dead   -> R-…, STANDING
   Supersedes: D-8b1e0d2               with a Decision: — marks the old one SUPERSEDED
   Refs:       F-3fa9c1e, D-004        relates this commit to existing entries (backlink)
   Due:        2026-10-15              modifier: a date the open item must be resolved by
   Owner:      sam                     modifier: who holds it
   Area:       hiring                  modifier: the workstream (default: the directory touched)
   Pin:        yes                     modifier: keep it in the session digest while in force
   Date:       2026-09-14              modifier: decided earlier -> `(recorded <commit date>)`
   ```
   Modifiers and Lore trailers (`Rejected:`, `Directive:`, `Constraint:`) belong to the entry
   trailer directly above them and are recorded into its body.
   **A decision that changes no file** — a direction, a priority, a call made in a meeting — is an
   empty commit: `git commit --allow-empty --only -m "decide: <subject>" -m "Decision: <one line>"`.
   It is dated, attributed, and in the log like any other.
   `.githooks/commit-msg` **rejects** a commit whose last paragraph carries none of these. The
   explicit opt-out is `Ledger: none — <reason, 3+ words>`; the escape hatch is
   `git commit --no-verify`. Merges, reverts, `fixup!`/`squash!`, `[bot]` authors and
   `EXEMPT_SUBJECTS` are exempt. `.githooks/post-commit` then syncs and commits this file itself.
2. **Checkpoint proposals.** At the end of a work chunk Claude says *"recording these: …"*; you
   approve, edit or decline.
3. **"note that …"** in chat → appended immediately as a `note` or `thought`. A thought is typed as
   a thought so it is visibly not a decision.

A digest of `OPEN` items and recent decisions is injected automatically at session start and after
compaction by `.claude/hooks/digest.sh` — so a cold session already knows this, without searching.

**Machines and branches.** Trailer-born entries are re-derived from git history on every clone
(from `SYNC_FROM` in `.claude/ledger.conf`) — there is no per-machine bookmark, so every clone
derives the same entries. Two branches or two machines inserting entries at once are merged
entry-wise by `.claude/hooks/ledger-merge.py` (`.gitattributes: merge=ledger`): no conflict,
`CLOSED` beats `OPEN`, and nothing is dropped. **Never delete an entry** — the next sync would
restore a trailer-born one. Mark it `SUPERSEDED` instead.

---

# Entries

<!-- newest first; ledger-sync.sh inserts directly below this marker -->
<!-- ENTRIES_START -->

## D-c7d8c48 · CLOSED · decision · - · 2026-09-23
the README leads with the workflow the user sees (Claude proposes one-line records and writes them into its commits; the user approves) and keeps the vocabulary and internals as reference
→ commit aaa8b3c

## D-0300a8f · CLOSED · decision · - · 2026-09-23
each commit's Directive/Constraint/Rejected trailers become Claude Code path rules in a gitignored .claude/rules/ledger/, regenerated at session start and after each commit
→ commit aaa8b3c

## F-0ec7cdf · STANDING · finding · - · 2026-09-23
Claude Code loads path-scoped rules from a gitignored .claude/rules/ subdirectory when it reads a matching file (checked with a headless run)
→ commit aaa8b3c

## D-b33dc3f · CLOSED · decision · - · 2026-09-23
.claude/hooks/ledger is the query side for any agent or person: context, directives, constraints, rejected, open, decisions, retired, stale, validate
→ commit aaa8b3c

## D-be290b3 · CLOSED · decision · - · 2026-09-23
the commit gate refuses a Decision that re-adopts a rejected alternative or a retired framing unless the commit supersedes it
· Rejected: an interactive commit builder like the paper's lore commit | Claude writes the message, and /ledger-note covers records without code
· Rejected: requiring the subject line to state intent, as Lore does | it clashes with Conventional Commits, which most repos already follow
→ commit aaa8b3c

## F-4e76afb · CLOSED · finding · bin · 2026-09-23
/ledger-status left v1-v2 repos out of the 'Behind template' list and padded it with blank lines
→ commit 18747db

## D-30f0af3 · CLOSED · decision · - · 2026-09-23
the session digest reports ledger records not shared or not seen (unpushed, not pulled, other branches and worktrees, other machines), from local refs only, never the network
→ commit 566a218

## D-dd97495 · CLOSED · decision · - · 2026-09-23
each machine writes its own status file into the private index, so machine names never enter a repository and two machines never conflict on it
→ commit 566a218

## D-245a95d · CLOSED · decision · - · 2026-09-23
branch and machine state is a precondition on a tidy (merge or pull first), not a trigger for one
· Directive: the skill never pushes, pulls or merges on its own when it reports unshared records; it offers
→ commit 566a218

## D-3d57516 · CLOSED · decision · - · 2026-09-23
the commit gate rejects a new entry that reads like a live one unless the commit Refs: or Supersedes: it; a Tidy: commit is exempt
→ commit b089e4f

## D-0e09e0e · CLOSED · decision · - · 2026-09-23
an open item mirroring another register's item is proposed for closing only when every item it cites is closed there
→ commit b089e4f

## F-b801e74 · CLOSED · finding · - · 2026-09-23
an open list over the digest cap re-triggered "tidy due" immediately after a tidy that had just reviewed it
→ commit b089e4f

## F-4e56fa1 · CLOSED · finding · - · 2026-09-23
the stale-rule check flagged rules that cite a closed finding on purpose, as a settled do-not-re-raise warning
→ commit fb3c9e8

## F-c4d9d50 · CLOSED · finding · - · 2026-09-23
in a git worktree every commit was a silent no-op for the ledger (GIT_DIR exported to hooks made the repo root resolve to .claude/hooks)
→ commit fc9d6cc

## D-ff761da · CLOSED · decision · - · 2026-09-23
post-merge only reports what a merge brought in; the next commit records it, because git still holds the merge state while post-merge runs
→ commit fc9d6cc

## D-0c2f6ea · CLOSED · decision · - · 2026-09-23
EXTERNAL_IDS names id prefixes of another register; the gate accepts them without a ledger entry and the sync keeps them as a pointer on the entry
→ commit fc9d6cc

## D-d55748a · CLOSED · decision · - · 2026-09-23
a tidy is suggested when the volume of work since the last Tidy: commit (entries + 3 x merges + commits / 5) passes TIDY_VOLUME over TIDY_MIN_DAYS days, or three times it in any span
→ commit 0025af7

## D-b8771f2 · CLOSED · decision · - · 2026-09-23
a tidy never deletes an entry; it compresses what is live, and there is no archive file
· Rejected: an archive file for dead entries | the sync's dedup, grep and the merge driver would all have to read two files
→ commit 0025af7

## D-f72c287 · CLOSED · decision · - · 2026-09-23
new entries are inserted by date, above the first entry dated on or before them; existing order is never rewritten
→ commit 0025af7

## D-4ceef34 · CLOSED · decision · - · 2026-09-23
Supersedes: <old> by <new> folds a duplicate into the entry that survives it
→ commit 0025af7

## F-266bd4e · CLOSED · finding · - · 2026-09-23
every session start rewrote a dashboard block's timestamp, so the index got a commit each time
→ commit 0025af7

## F-82b00ec · STANDING · finding · - · 2026-09-23
about half of a research repo's 79 decisions were not about code (method, paper scope, slides, documentation) and were captured because they travelled with committed docs
→ commit 0025af7

## F-a9eadb5 · CLOSED · finding · - · 2026-09-23
the sync appended table rows into a decisions log kept as dotted lines
→ commit 8d1b1f8

## F-03d4225 · CLOSED · finding · - · 2026-09-23
install.sh --upgrade committed whatever the user already had staged along with the upgrade
→ commit 977a250

## D-a7ab56f · CLOSED · decision · - · 2026-09-23
entry ids are content hashes of the entry text; legacy sequential ids stay valid and are never renumbered
· Rejected: re-keying colliding sequential ids at merge time | a Closes: written on the branch then points at the wrong entry
→ commit 9d9fbe4

## D-fdde1b7 · CLOSED · decision · - · 2026-09-23
the ledger is re-derived from git log since a committed SYNC_FROM floor on every run; there is no per-machine sync state
· Rejected: a gitignored per-machine bookmark | two clones of one repo derive different ledgers
→ commit 9d9fbe4

## D-74f6221 · CLOSED · decision · - · 2026-09-23
LEDGER.md and the DECISIONS.md log merge entry-wise through a git merge driver (merge=ledger), never textually
→ commit 9d9fbe4

## D-38e1459 · CLOSED · decision · - · 2026-09-23
the commit gate is a git commit-msg hook that calls the sync's own trailer reader, so the gate and the sync cannot disagree
→ commit 9d9fbe4

## D-3c1386a · CLOSED · decision · - · 2026-09-23
Finding: records a settled fact (STANDING); only Opens: and Action: create open items
→ commit 9d9fbe4

## D-6452a38 · CLOSED · decision · - · 2026-09-23
committed git hooks are activated as per-clone shims in the hooks dir that keep existing hooks; core.hooksPath is never set
→ commit 9d9fbe4

## D-6741609 · CLOSED · decision · - · 2026-09-23
reading the ledger never writes the working tree; only the post-commit hook writes it, and it commits what it writes
→ commit 9d9fbe4

## D-9e6cd0d · CLOSED · decision · - · 2026-09-23
headless sessions (claude -p, SDK scripts) get no digest and run no sync
→ commit 9d9fbe4

## D-0700721 · CLOSED · decision · - · 2026-09-23
a decision with no file change is recorded as an empty commit carrying the trailer, made when the decision is approved
→ commit 9d9fbe4

## D-a927d9e · CLOSED · decision · - · 2026-09-23
the tool ships as a plain skill cloned into ~/.claude/skills/living-ledger, not as a plugin
· Rejected: a Claude Code plugin | its install path changes with every version and its commands are namespaced
→ commit 9d9fbe4

## D-3a1441e · CLOSED · decision · - · 2026-09-23
the tool repository holds no user data; each user's cross-repo index is their own private repository
→ commit 9d9fbe4

## R-1f02f23 · STANDING · retired · - · 2026-09-23
a PreToolUse Bash hook as the commit gate — it sees only Claude's commits and has to parse shell to find the message
→ commit 9d9fbe4

## R-d027735 · STANDING · retired · - · 2026-09-23
core.hooksPath=.githooks to activate the committed git hooks — it switches off every hook in .git/hooks, Git LFS included
→ commit 9d9fbe4

## R-f047556 · STANDING · retired · - · 2026-09-23
sequential max+1 entry ids
→ commit 9d9fbe4

## F-5eb5445 · OPEN · finding · - · 2026-09-23
capture still needs a commit — a decision nobody states in a session never reaches the ledger
→ commit 9d9fbe4
