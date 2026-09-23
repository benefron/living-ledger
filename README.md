# living-ledger

**Project memory for Claude Code that lives in git.** Every decision, finding, open question,
action and dead end is recorded as a trailer on the commit that made it, collected into a
greppable `LEDGER.md`, and handed to every new session as a short digest — so a cold session
starts from what was already settled instead of re-deriving it, and nobody hears *"we had this
discussion before"* again.

It works for code, and for the parts of a project that are not code: direction, scope,
priorities, a call made in a meeting, a deadline you are waiting on. Those are commits too — empty
ones — so they are dated, attributed, merged across branches and machines, and never out of sync
with the history that enacted them.

It implements the **Lore** pattern — git commit trailers as a structured knowledge protocol for
AI coding agents (Stetsenko, [arXiv:2603.15566](https://arxiv.org/abs/2603.15566), 2026) — and
adds a materialised read surface, a session digest and a cross-repo dashboard on top.

```text
$ git commit -m "feat: stream frames through a bounded queue" -m "Profiling showed 70% of
encoder time waiting on the lock; a queue removes the contention." -m "Decision: use a
single-writer queue for the encoder instead of a lock
Rejected: fine-grained locks | deadlocked under the stress test
Opens: the queue has no back-pressure yet
Due: 2026-10-01"
living-ledger: ledger updated and committed (after 744a3d8).
```

```markdown
## D-7ab377b · CLOSED · decision · src/encoder · 2026-09-23
use a single-writer queue for the encoder instead of a lock
· Rejected: fine-grained locks | deadlocked under the stress test
→ commit 744a3d8

## F-6e63234 · OPEN · finding · src/encoder · 2026-09-23
the queue has no back-pressure yet
· Due: 2026-10-01
→ commit 744a3d8
```

…and the next session opens with:

```text
# Project ledger digest (auto-injected; full file: ~/code/app/docs/LEDGER.md)
41 entries · 3 open (1 overdue) · 2 pinned · 4 retired framings

## Open (3) — problems, questions, actions; do not re-discover these
- F-6e63234 [src/encoder] (due 2026-10-01) the queue has no back-pressure yet
…
## Retired — settled; do NOT re-propose (4)
- R-0c4f7a1 "a nightly batch job is good enough"
```

## Install

Requires git, python3 (3.8+), bash, and [Claude Code](https://code.claude.com).

```bash
git clone https://github.com/benefron/living-ledger ~/.claude/skills/living-ledger
~/.claude/skills/living-ledger/install.sh --global-only
```

`--global-only` installs the `/ledger-init`, `/ledger-status`, `/ledger-note`, `/ledger-tidy`
and `/ledger-setup` commands, creates your local cross-repo index at `~/.claude/ledger/`, and adds one
user-level `SessionStart` hook (it suggests `/ledger-init` once in a repo without a ledger, and
flags repos running an older template; `LL_NO_GLOBAL_HOOK=1` skips it).

Then, in a repository — ideally before its first commit:

```text
/ledger-init
```

(or `~/.claude/skills/living-ledger/install.sh /path/to/repo`). Commit what it created. Every
clone of that repo now carries the ledger, its hooks and its history; there is nothing else to
install for collaborators beyond Claude Code itself.

**Working across machines?** Run `/ledger-setup` once per machine to back `~/.claude/ledger/` with
a private git repo of your own. It holds only your dashboard (which repos, what is open in each);
the ledgers themselves always live in their repos.

## The vocabulary

In the **last paragraph** of a commit message, one per line (a long one may wrap):

| Trailer | Records | Entry |
|---|---|---|
| `Decision: <line>` | a settled choice — code, scope, direction, anything | `D-…` CLOSED (in force) |
| `Finding: <line>` | a settled fact or result | `F-…` STANDING |
| `Opens: <line>` | an open problem or question | `F-…` OPEN |
| `Fixed: <line>` | a problem found and fixed in this commit | `F-…` CLOSED |
| `Action: <line>` | a to-do | `A-…` OPEN |
| `Retires: <framing>` | an approach that is dead — never re-propose | `R-…` STANDING |
| `Closes: <id>` | resolves an open item | → CLOSED |
| `Supersedes: <id>` | with a `Decision:`: replaces an earlier decision | → SUPERSEDED |
| `Supersedes: <old> by <new>` | folds a duplicate into its survivor | → SUPERSEDED |
| `Refs: <id>, …` | relates this commit to existing entries | backlink |
| `Ledger: none — <reason>` | the explicit opt-out (≥ 3 words of reason) | — |
| `Tidy: <summary>` | marks a tidy pass | — |

Modifiers attach to the entry trailer above them: `Due: 2026-10-01`, `Owner: sam`, `Area: hiring`,
`Pin: yes` (keep it in every digest while in force), `Date: 2026-09-14` (decided earlier than
committed). Lore's own trailers (`Rejected:`, `Constraint:`, `Directive:` …) are recorded into the
entry's body. Full schema: [`reference/entry-format.md`](reference/entry-format.md).

A decision with no file change is an empty commit:

```bash
git commit --allow-empty --only -m "decide: interview loop" -m "Decision: two rounds, no take-home"
```

The gate also stops the commonest source of duplicates — a decision recorded when it is planned
and again, reworded, when it is enacted: a new entry that reads like a live one is rejected until
the commit says how they relate (`Refs:` if it enacts it, `Supersedes:` if it replaces it, or a
`Refs:` beside the new entry if it is genuinely different). Content-hash ids already merge exact
repeats; this catches the rewordings.

Claude does all of this for you: the skill fires when a decision, finding or dead end comes up in
conversation, proposes the one-line record, and commits it when you approve.

## How it works

```text
 commit ──► commit-msg gate ──► post-commit: ledger-sync ──► LEDGER.md (+ DECISIONS.md log)
             rejects: no trailer,          derives entries from           auto-committed as
             a trailer outside the         git log since SYNC_FROM;       "chore: ledger sync"
             last paragraph, an            content-hash ids               (only the ledger files)
             unknown id, an entry that
             restates a live one

 session start ──► digest.sh ──► bounded digest (overdue, open by area, pinned, recent, retired)
                                  + housekeeping: stale rules, lint, hooks activated, upgrade due

 merge / pull ──► merge=ledger driver: entries merged by id, never a textual conflict
```

- **Ids are content hashes** (`D-3fa9c1e`), not counters: the same entry gets the same id on
  every clone, branch, worktree and cloud session, so parallel work never collides and a
  squash-merge never renumbers anything. Legacy sequential ids (`F-014`) keep working.
- **The ledger is derived, not maintained**: every clone re-derives the same entries from
  `git log` since the committed `SYNC_FROM` floor. There is no per-machine state to drift.
- **Reading never writes.** The session digest is built from a temporary copy; only the
  post-commit hook writes the ledger, and it commits what it writes.
- **Level 2 is the commit body.** The *why* of a decision lives in the message that carried it;
  `DECISIONS.md` holds longer reasoning, append-only. See the three-levels table in the template.

## Keeping it true: `/ledger-tidy`

A ledger drifts the way any register does: facts left open, the same decision recorded when it
was planned and again when it was enacted, an old decision quietly contradicted by a new one, a
path rule citing a finding that closed weeks ago. The digest is only useful while it is true.

The session digest says **Tidy due** when the *volume of work* since the last tidy — new entries,
plus 3 per merge, plus 1 per 5 commits — has reached `TIDY_VOLUME` (25) over at least
`TIDY_MIN_DAYS` (7) days, or three times that volume in any span (a one-day burst of fifty
entries needs a tidy as much as a busy fortnight does), or when the open list outgrew the digest.
Claude offers it once, at a natural pause.

`/ledger-tidy` builds a report of candidates — open items that read as settled, overdue and
aging items, near-duplicates and possible contradictions, empty entries, long-pinned entries,
decisions whose reasoning was never written, stale rules, and other files in the repo that keep
their own lists — proposes a fix for each, and applies what you approve in one commit
(`Closes:`, `Supersedes: <old> by <new>`, a few status edits, and a `Tidy:` trailer the next
check counts from). Nothing is deleted: a tidy *compresses what is live* — what the digest shows
and a session has to weigh — while the history stays in the one file every tool reads.

## What runs where

Everything is local shell + python, readable in `templates/`. Nothing phones home.

| Piece | When | Touches |
|---|---|---|
| `.githooks/commit-msg` | every `git commit` in the repo (you, Claude, an IDE) | reads the message and the ledger; can reject the commit |
| `.githooks/post-commit` | after a commit | `LEDGER.md`, `DECISIONS.md`; makes the `chore: ledger sync` commit |
| `.claude/hooks/digest.sh` | Claude Code session start / after compaction | reads the repo; activates the git hooks on a fresh clone (announced); updates your local index |
| `.claude/hooks/ledger-index-push.sh` | session start (async) / session end | commits + pushes `~/.claude/ledger` **only if you gave it a remote** |
| `bin/ledger-session.sh` | session start, user-level | reads only; prints a one-line suggestion |

**Branches, worktrees and machines.** At session start the digest also says where ledger records
exist that this checkout has not shared or seen — unpushed here, on the upstream but not pulled
(as of the last fetch; the session never touches the network for it), on another local branch or
worktree, or unpushed on another of your machines. Each machine writes its own one-line-per-repo
status file into your private index (`hosts/<machine>.tsv`), so `/ledger-status` on any machine
shows "on rig-mac: 2 records not pushed". Machine names live only in that private index, never
in a repository. A "Tidy due" line says what to merge or pull first, so a tidy judges the whole
picture.

Git never runs committed hooks by itself. On a fresh clone, the first Claude Code session
installs a small **shim** per hook into the clone's `.git/hooks/` (an existing hook, e.g. Git
LFS's, is kept and still runs first) and says so in the session. Set `AUTO_HOOKS=no` in
`.claude/ledger.conf` (or `LEDGER_AUTO_HOOKS=0`) to get an instruction instead. `core.hooksPath`
is never touched. Headless runs (`claude -p`, SDK scripts) get no digest and run no sync.

**Public repositories:** the ledger and every trailer are as public as the repo. `/ledger-init`
warns when the remote is public; keep personal or strategic reasoning in a private repo.

## Configuration

`.claude/ledger.conf` (committed): `LEDGER_PATH`, `DECISIONS_PATH`, `REPO_ID`, `SYNC_FROM`,
optional `AUDIENCE_SURFACE`, `EXEMPT_SUBJECTS` / `EXEMPT_AUTHORS` (regexes — commits by pipelines
and cron jobs; repeated trailer-less subjects are detected at install), `AUTO_HOOKS`.

Environment: `LEDGER_SKIP=1` (skip the gate and sync for one command), `LEDGER_DIGEST=on|off`,
`LEDGER_AUTO_HOOKS=0`, `LEDGER_HOME` (index location), `LL_MAX_OPEN` / `LL_MAX_RECENT` (digest caps).

## Limitations, honestly

- **Capture takes a commit.** That covers far more than code — anywhere decisions travel with
  committed work: docs, a paper, a deck script, a plan (see the field notes). Where nothing gets
  committed, the only path in is the empty commit Claude makes when you approve a record; a
  decision nobody states never lands. The digest shows what was recorded, not what was thought.
- **One extra commit per recorded commit** (`chore: ledger sync`). It is the price of keeping the
  ledger committed and identical everywhere; the dashboard does not count those.
- **A ledger is only as good as its tidying.** Open items that are really facts, or decisions
  recorded twice (once planned, once enacted), dilute the digest. The vocabulary (`Finding:` vs
  `Opens:`, `Refs:` for enactment, `Supersedes:`) prevents most of it; `/ledger-tidy` folds the
  rest, and says when it is due.
- The digest is capped (~2–3k tokens); older material is grep-only by design.

## Field notes

Developed and dogfooded across six real repositories — research code, a hardware controller, a
data pipeline, and a non-code planning workspace. In the research repository about half of the
79 recorded decisions were not about code at all: scientific method (what is declared, what is
measured and how), the scope of two papers and which repository owns what, what the slides may
and may not claim, and how the project documents itself. They were captured because they
travelled with committed docs and plans. The planning workspace is the counter-example: its work
was never committed, so almost nothing was recorded — which is what the empty-commit path and
`Due:`/`Action:`/`Pin:` are for. v4 is the result of auditing all six: it
fixes id collisions between parallel branches and machines, trailers silently dropped when a line
wrapped, "open" lists full of settled facts, auto-sync failing when `DECISIONS.md` was
gitignored, `core.hooksPath` silently disabling Git LFS, and the digest leaking into headless
pipeline calls. See [`CHANGELOG.md`](CHANGELOG.md) and this repo's own [`LEDGER.md`](LEDGER.md).

## Development

```bash
bash tests/run_tests.sh      # end-to-end: install, gate, sync, merge, upgrade, digest, index
python3 tests/test_merge.py  # the merge driver
```

## License

MIT — see [`LICENSE`](LICENSE). The Lore pattern is Ivan Stetsenko's; this is an independent
implementation.
