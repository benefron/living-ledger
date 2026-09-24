# Decisions record — the reasoning behind the ledger

**Level 2 of three.** `LEDGER.md` holds the *fact* of each decision (one line, generated from
the commit trailer). The *reasoning* — why, on what evidence, against what alternative — lives in
the body of the commit that carried the `Decision:` trailer (`git show <sha>`), and, when it is
bigger than a commit body, here. Level 3 — a deck script, a paper, the README's claims — is whatever audience surface
this repo has, if it has one; `.claude/ledger.conf` names it under `AUDIENCE_SURFACE=`, and it is
updated on request, never automatically.

A decision recorded here but not in the ledger is invisible to future sessions. A decision in the
ledger but not here is a verdict with no argument behind it. Write both.

**This file is append-only, and it keeps its history.** Every section is dated. A decision that is
later superseded is **never deleted and never edited**: it gains a `**Superseded by:**` line, and
the section that replaces it opens with `**Supersedes:**`. The corrections are the record — tidying
them away is the exact failure this system exists to prevent.

**How to add one.** `ledger-sync.sh` has already appended the dated fact to the **log** at the
bottom for you. Write the reasoning as a section here, newest first, using this template:

```markdown
## D-xxxxxxx · <short title> · <YYYY-MM-DD>

**Supersedes:** D-yyyyyyy · <date>      <!-- omit unless it replaces an earlier decision -->

**What was decided.** <quote the ledger entry verbatim — level 1 and level 2 must agree>

**Why.** <the evidence: numbers, measurements, the `F-`/`D-` ids that forced it. Not "it seemed
cleaner" — what was observed.>

**What was rejected.** <the alternative that was seriously considered, and the specific reason it
lost. This is the half that stops the question being re-opened in three months.>

**Where it lives.** <file:line, config key, module — where a reader verifies the decision is real>

**Ledger id + sha.** D-xxxxxxx · `<short sha>`

**Validation pending.** <what would still falsify or confirm this, or "none — settled">
```

And on the section it replaces, add one line — nothing else changes:

```markdown
**Superseded by:** D-xxxxxxx · <date>
```

---

# Sections

<!-- newest first; written by hand -->
<!-- SECTIONS_START -->

## D-7269818 · Closes: closes a finding, never a decision, retired framing or note · 2026-09-24

**What was decided.** "a Closes: trailer resolves an open item or a finding, including one
recorded as a fact; a decision, a retired framing or a note is never closed — the gate refuses it
and points to Supersedes: or Refs:"

**Why.** F-e118b73: the sync only flipped OPEN entries, so `Closes:` on anything else added a
`✓ closed by` line and changed nothing. Since v4 made `Finding:` a STANDING fact (D-3c1386a), the
common case is a problem written as `Finding:` out of v3 habit and closed once fixed. The entry
stayed STANDING, and the digest kept listing it under "Recently decided / established". Closing
it now gives the same entry as `Opens:` followed by `Closes:`, a resolved finding, which is what
the user meant. `Closes:` on a decision had the same silent no-op: the ✓ line said closed, and the
decision stayed in force.

**What was rejected.** *Flipping every STANDING entry to CLOSED* (retired framings and notes too).
Closing a retired framing would take it off the "do NOT re-propose" list, and out of the gate's
re-adoption check, without the `Decision:` + `Supersedes:` that D-be290b3 requires. *Refusing
`Closes:` on any STANDING entry.* A fixed problem that was written as `Finding:` would then have
no honest path: `Supersedes:` says replaced, not resolved. The only other route is a hand edit to
OPEN first.

**Where it lives.** `close_refusal` in `templates/hooks/_ledger_parse.py`. The gate
(`check_body`) and the sync (`ledger-sync.sh`, the `Closes` branch) both call it. The tidy
report's "A Closes: that changed nothing" section catches entries an older sync left behind: a
closed entry is never re-flipped on a re-scan, because a hand re-open has to stick.

**Ledger id + sha.** D-7269818 · (the commit that closes F-e118b73)

**Validation pending.** None. Settled. Tests: section 5b of `tests/run_tests.sh`.

## D-add0c44 · Prompt-time recall, calibrated at tidy · 2026-09-24

**What was decided.** "each message the user types is matched against the whole ledger, and up to
three entries the session digest did not show are put in front of Claude when they score at least
RECALL_MIN (2.0)" — and the threshold is recalibrated at `/ledger-tidy` from what was used.

**Why.** The digest is bounded; in the largest real ledger (pressure-simulation, 213 entries) 163
entries were reachable only by grep, and grep needs the right word. Before building the hook, 167
messages the user typed in pressure-simulation and sensoryforge were replayed offline. For each
one, recall ran against the ledger as it stood at that moment, excluding what the digest showed.
A separate agent then rated every hit relevant, tangential or noise without seeing its score:

| threshold | fires on | relevant | noise | relevant entries the agent never looked up |
|---|---|---|---|---|
| 1.5 | 17% | 62% | 29% | 17 |
| 2.0 | 13% | 81% | 12% | 10 |
| 2.5 | 8% | 83% | 6% | 6 |

Scores are BM25 divided by the square root of the message's term count; raw BM25 let long pasted
reports out-score short questions. A match must include two words outside a short list of chat
words ("give", "run", "need", "call"…), which removed most small-talk hits. Short questions in the
user's own words gained the most; long pasted reports produced most of the remaining noise.

Calibration uses a signal that is visible without asking the user: the skill cites an entry's id
when a recalled entry shapes its answer. Each clone logs what was shown and what was held back
just under the threshold. At a tidy, `recall-stats` reads the session transcripts back: if the
weakest band (threshold to threshold + 0.5) is cited less than 30% of the time, it proposes
raising the threshold; if 30% or more of the held-back entries were looked up anyway, it proposes
lowering it. It needs 30 recalls since the last change, and moves 0.25 at a time within 1.5–3.5.
The last commit that changed `RECALL_MIN` resets the count, so the history lives in git.

**What was rejected.** A plan-time check (a PreToolUse hook on ExitPlanMode that searches the
plan): in the 19 real plans replayed, every strong hit was already cited by the plan, because the
planning agent searches the ledger itself. Raw BM25 scores as the threshold: they grow with
message length. Calibrating automatically without review: a threshold change alters what every
session sees, so it goes through the tidy's approval like everything else.

**Where it lives.** `recall`, `cmd_recall_hook`, `recall_stats` in
`templates/hooks/_ledger_parse.py`; `templates/hooks/ledger-recall.sh`; the per-session list the
digest writes; `RECALL_MIN` / `RECALL_MAX` / `RECALL` in `ledger.conf`; the tidy report's last
section.

**Ledger id + sha.** D-add0c44 · `58f67cc`

**Validation pending.** The replay is small (two repositories, one judge). The calibration log is
the real test: the first tidy with 30 recalls says whether 2.0 holds.

## D-a7ab56f · Content-hash entry ids · 2026-09-23

**What was decided.** "entry ids are content hashes of the entry text; legacy sequential ids stay
valid and are never renumbered"

**Why.** Through v3 an id was `max+1` over the local file, allocated when the sync ran — per
branch, per worktree, per machine. In the six repositories audited for v4 this produced every
failure a counter can: three parallel branches each allocated the same three findings and had to
be renumbered by hand; a `Closes:` written on a branch for its own finding closed an unrelated one
after the merge (and a re-open commit followed); two machines hold different entries under the
same decision id and will conflict on the next pull; and the stale numbers were already cited in
a changelog, code comments and immutable commit subjects. A content hash is the same everywhere
the text is the same, needs no coordination, and survives rebase and squash. First proposed in the
cloud review of the method (`849de93`, in the index repository); kept.

**What was rejected.** Keeping counters and re-keying collisions at merge time — a `Closes:` or a
citation written on the branch would then point at the wrong entry, which is the bug itself.
Sha-derived ids — a rebase or squash changes the sha.

**Where it lives.** `hash_id()` in `templates/hooks/_ledger_parse.py`; legacy handling in the
sync's `legacy_text` dedup and the merge driver's re-keying.

**Validation pending.** Whether 7 hex digits per prefix stay collision-free in very large ledgers
(~1 in 10^4 at 2,000 entries of one type); the merge driver would surface one as two entries.

## D-fdde1b7 · Derived from git, no per-machine state · 2026-09-23

**What was decided.** "the ledger is re-derived from git log since a committed SYNC_FROM floor on
every run; there is no per-machine sync state"

**Why.** v2 moved the "synced up to" bookmark out of the ledger into a gitignored file so advancing
it would not dirty the tree — which made sync state per clone: a fresh clone started from HEAD and
silently never recorded earlier trailers, and a hand-edited bookmark skipped some. Deriving from
the full range every run is cheap (thousands of commits in well under a second), idempotent via
the ids, and identical on every clone. The committed floor keeps an upgrade from re-deriving
history that predates the ledger. From the same cloud review (`849de93`), plus the floor.

**What was rejected.** The gitignored bookmark (v2–v3). An unbounded full-history scan — on an
upgrade it would re-add every pre-ledger trailer.

**Where it lives.** `templates/hooks/ledger-sync.sh`, `SYNC_FROM` in `.claude/ledger.conf`,
`ll_sync_floor` (which migrates the v1 marker and the v2–v3 bookmark).

**Validation pending.** none — settled.

## D-38e1459 · One trailer reader for the gate and the sync · 2026-09-23

**What was decided.** "the commit gate is a git commit-msg hook that calls the sync's own trailer
reader, so the gate and the sync cannot disagree"

**Why.** v3's gate was POSIX awk, the sync python, and both rejected a trailer paragraph with any
wrapped line — so agents wrapping at 72 columns lost whole trailer blocks without a word: 32
commits in one repository, 8 in another, including findings written "so they are not
re-discovered". The v4 reader accepts wrapped and indented continuations, and the gate rejects any
ledger line that falls outside the block instead of letting the sync drop it. A git hook (not a
Claude Code hook) because it must see every commit — the terminal, an IDE, another agent.

**What was rejected.** A PreToolUse Bash guard (proposed in `849de93`): it sees only Claude's
commits and has to parse shell quoting and heredocs to find the message. A pure-shell gate: the
duplicate parser is exactly what drifted.

**Where it lives.** `trailer_lines()` and `check_msg()` in `_ledger_parse.py`;
`templates/githooks/commit-msg` is a thin wrapper.

**Validation pending.** A git client whose hook PATH lacks python3 lets commits through unchecked
(with a warning) rather than blocking them.

## D-3c1386a · Finding: is a fact; open items are explicit · 2026-09-23

**What was decided.** "Finding: records a settled fact (STANDING); only Opens: and Action: create
open items"

**Why.** Every `Finding:` used to open an item. In the audited repositories 45–90% of "open"
findings were settled results, fixed in the same commit, or refuted — one digest announced 50
open findings, another hid real open bugs behind the cap under a pile of facts. The digest's open
list is what a new session trusts most, so it must only hold things someone still has to do.
`Fixed:` covers the found-and-fixed case directly.

**What was rejected.** Keeping `Finding:` open and adding `Learned:` for facts — agents already
write `Finding:` for facts, so the default had to match the use.

**Where it lives.** `KINDS` in `_ledger_parse.py`.

**Validation pending.** Existing ledgers need one triage pass after upgrading (part of
`/ledger-init --upgrade`).

## D-6452a38 · Hook shims, never core.hooksPath · 2026-09-23

**What was decided.** "committed git hooks are activated as per-clone shims in the hooks dir that
keep existing hooks; core.hooksPath is never set"

**Why.** v3 activated `.githooks/` by setting `core.hooksPath`, which silently switched off every
hook in `.git/hooks` — one repository lost its Git LFS hooks that way. A shim per hook keeps
whatever was there (renamed `<name>.pre-ledger`, run first) and is visible: the session that
installs it says so. A repo already on a foreign `core.hooksPath` (husky) is left alone and told
how to chain.

**What was rejected.** `core.hooksPath` (v3). Not activating at all on fresh clones — cloud
sessions are always fresh clones, so enforcement would never run there.

**Where it lives.** `ll_activate_git_hooks` in `lib/common.sh`; `ledger-activate.sh`; the
`AUTO_HOOKS=no` switch.

**Validation pending.** none — settled.

## D-0700721 · Record decisions when they are made · 2026-09-23

**What was decided.** "a decision with no file change is recorded as an empty commit carrying the
trailer, made when the decision is approved"

**Why.** The one non-code repository in the audit recorded two decisions in nine days: its work
was never committed, so "put the trailer on the next commit" never happened, and the real
strategy — a checkpoint date, a deadline, a weekly pace — lived in untracked files. An empty
commit (`--allow-empty --only`, so nothing staged rides along) is dated, attributed, merges across
machines like any entry, and needs no second capture path to keep in sync. `Due:`, `Action:` and
`Pin:` exist for the same kind of work.

**What was rejected.** Writing decisions straight into `LEDGER.md` by hand — a second path that
bypasses the gate, the log and the ids. (Notes and thoughts still are, deliberately: they are not
decisions.)

**Where it lives.** The skill's "record it now" step; `/ledger-note`.

**Validation pending.** Whether the skill actually proposes records in non-code conversations
often enough — watch the dashboard's "commits since last entry" on non-code repos.


---

# Log — every recorded decision, in order

Appended automatically by `.claude/hooks/ledger-sync.sh` from `Decision:` and `Retires:` trailers
(a section heading here should start with the same id, so the two can be checked against each other),
so level 2 always holds at least the dated fact even before anyone writes the reasoning above.
Do not hand-edit between the markers.

| Date | Id | One line | Commit |
|---|---|---|---|
<!-- DECISIONS_LOG_START -->
| 2026-09-23 | D-a7ab56f | entry ids are content hashes of the entry text; legacy sequential ids stay valid and are never renumbered | `9d9fbe4` |
| 2026-09-23 | D-fdde1b7 | the ledger is re-derived from git log since a committed SYNC_FROM floor on every run; there is no per-machine sync state | `9d9fbe4` |
| 2026-09-23 | D-74f6221 | LEDGER.md and the DECISIONS.md log merge entry-wise through a git merge driver (merge=ledger), never textually | `9d9fbe4` |
| 2026-09-23 | D-38e1459 | the commit gate is a git commit-msg hook that calls the sync's own trailer reader, so the gate and the sync cannot disagree | `9d9fbe4` |
| 2026-09-23 | D-3c1386a | Finding: records a settled fact (STANDING); only Opens: and Action: create open items | `9d9fbe4` |
| 2026-09-23 | D-6452a38 | committed git hooks are activated as per-clone shims in the hooks dir that keep existing hooks; core.hooksPath is never set | `9d9fbe4` |
| 2026-09-23 | D-6741609 | reading the ledger never writes the working tree; only the post-commit hook writes it, and it commits what it writes | `9d9fbe4` |
| 2026-09-23 | D-9e6cd0d | headless sessions (claude -p, SDK scripts) get no digest and run no sync | `9d9fbe4` |
| 2026-09-23 | D-0700721 | a decision with no file change is recorded as an empty commit carrying the trailer, made when the decision is approved | `9d9fbe4` |
| 2026-09-23 | D-a927d9e | the tool ships as a plain skill cloned into ~/.claude/skills/living-ledger, not as a plugin | `9d9fbe4` |
| 2026-09-23 | D-3a1441e | the tool repository holds no user data; each user's cross-repo index is their own private repository | `9d9fbe4` |
| 2026-09-23 | R-1f02f23 | a PreToolUse Bash hook as the commit gate — it sees only Claude's commits and has to parse shell to find the message | `9d9fbe4` |
| 2026-09-23 | R-d027735 | core.hooksPath=.githooks to activate the committed git hooks — it switches off every hook in .git/hooks, Git LFS included | `9d9fbe4` |
| 2026-09-23 | R-f047556 | sequential max+1 entry ids | `9d9fbe4` |
| 2026-09-23 | D-d55748a | a tidy is suggested when the volume of work since the last Tidy: commit (entries + 3 x merges + commits / 5) passes TIDY_VOLUME over TIDY_MIN_DAYS days, or three times it in any span | `0025af7` |
| 2026-09-23 | D-b8771f2 | a tidy never deletes an entry; it compresses what is live, and there is no archive file | `0025af7` |
| 2026-09-23 | D-f72c287 | new entries are inserted by date, above the first entry dated on or before them; existing order is never rewritten | `0025af7` |
| 2026-09-23 | D-4ceef34 | Supersedes: <old> by <new> folds a duplicate into the entry that survives it | `0025af7` |
| 2026-09-23 | D-ff761da | post-merge only reports what a merge brought in; the next commit records it, because git still holds the merge state while post-merge runs | `fc9d6cc` |
| 2026-09-23 | D-0c2f6ea | EXTERNAL_IDS names id prefixes of another register; the gate accepts them without a ledger entry and the sync keeps them as a pointer on the entry | `fc9d6cc` |
| 2026-09-23 | D-3d57516 | the commit gate rejects a new entry that reads like a live one unless the commit Refs: or Supersedes: it; a Tidy: commit is exempt | `b089e4f` |
| 2026-09-23 | D-0e09e0e | an open item mirroring another register's item is proposed for closing only when every item it cites is closed there | `b089e4f` |
| 2026-09-23 | D-30f0af3 | the session digest reports ledger records not shared or not seen (unpushed, not pulled, other branches and worktrees, other machines), from local refs only, never the network | `566a218` |
| 2026-09-23 | D-dd97495 | each machine writes its own status file into the private index, so machine names never enter a repository and two machines never conflict on it | `566a218` |
| 2026-09-23 | D-245a95d | branch and machine state is a precondition on a tidy (merge or pull first), not a trigger for one | `566a218` |
| 2026-09-23 | D-c7d8c48 | the README leads with the workflow the user sees (Claude proposes one-line records and writes them into its commits; the user approves) and keeps the vocabulary and internals as reference | `aaa8b3c` |
| 2026-09-23 | D-0300a8f | each commit's Directive/Constraint/Rejected trailers become Claude Code path rules in a gitignored .claude/rules/ledger/, regenerated at session start and after each commit | `aaa8b3c` |
| 2026-09-23 | D-b33dc3f | .claude/hooks/ledger is the query side for any agent or person: context, directives, constraints, rejected, open, decisions, retired, stale, validate | `aaa8b3c` |
| 2026-09-23 | D-be290b3 | the commit gate refuses a Decision that re-adopts a rejected alternative or a retired framing unless the commit supersedes it | `aaa8b3c` |
| 2026-09-23 | D-a188554 | the commit gate's rejection message shows three examples and the opt-out and says Claude normally writes them; the full vocabulary lives at the top of the ledger | `ce6e809` |
| 2026-09-24 | D-14aa29c | `ledger search <words>` ranks every ledger entry, including retired and superseded ones, by BM25 over its text and annotations | `f082dda` |
| 2026-09-24 | D-add0c44 | each message the user types is matched against the whole ledger, and up to three entries the session digest did not show are put in front of Claude when they score at least RECALL_MIN (2.0) | `58f67cc` |
| 2026-09-24 | D-f4db0bf | the recall threshold is recalibrated at /ledger-tidy from whether recalled ids were cited, in steps of 0.25 between 1.5 and 3.5 once 30 recalls are logged, and the change is committed to ledger.conf | `58f67cc` |
| 2026-09-24 | D-7269818 | a Closes: trailer resolves an open item or a finding, including one recorded as a fact; a decision, a retired framing or a note is never closed — the gate refuses it and points to Supersedes: or Refs: | `d1d6187` |
<!-- DECISIONS_LOG_END -->
