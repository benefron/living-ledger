---
name: living-ledger
description: >-
  Living project memory for a repo: decisions, findings, open questions, actions and retired
  approaches, captured from git commit trailers, injected into every session, and rolled up
  across repos. Invoke WITHOUT being asked whenever the user (a) makes, reverses, or locks a
  decision — about code or anything else in the project: direction, scope, priorities, people,
  deadlines ("let's go with", "we decided", "actually no", "scrap that", "changed my mind",
  "we're not doing X", "final answer", "lock this in"); (b) reports a finding or root cause
  ("turns out", "the bug is", "root cause", "the real problem is", "discovered that"); (c)
  retires an approach ("that's dead", "stop proposing X", "we already tried that"); (d) sets a
  to-do or deadline worth tracking ("we need to", "by Friday", "waiting on"); (e) asks to
  capture or orient ("note that", "remember that", "where did we land on", "what's still open",
  "did we decide", "catch me up", "is this still current"); (f) asks across repos ("what's open
  across my projects", "which repos need attention"); (g) wants the ledger cleaned up ("tidy the
  ledger", "clean up the open list", "compress the ledger", "the digest is noisy"); or (h) sets up
  tracking, or runs /init in a repo with no LEDGER.md. Also handles /ledger-init, /ledger-status,
  /ledger-note, /ledger-tidy, /ledger-setup. Implements the Lore pattern (git commit trailers as a structured knowledge
  protocol, arXiv:2603.15566). Do NOT use for ordinary code edits, or for questions the injected
  ledger digest already answers.
---

# Living Ledger

A per-repo register of **decisions, findings, open questions, actions and retired approaches**,
generated from git commit trailers, injected into every session as a bounded digest, and rolled
up into one cross-repo dashboard. It exists so a cold session — yours tomorrow, or a fresh agent
— starts from what was already settled instead of re-deriving it.

It implements **Lore** (Stetsenko, arXiv:2603.15566, 2026): the commit is *"the atomic unit of
institutional knowledge"*, carried in native git trailers because a commit and its message
*"cannot drift out of sync"*. See `reference/lore-paper.md`. The ledger adds a materialised,
greppable read surface (`LEDGER.md`) and a session digest on top; git stays the source of truth.

## The trailer vocabulary

In the **last paragraph** of a commit message, one per line (a long one may wrap):

| Trailer | Records | Entry |
|---|---|---|
| `Decision: <one line>` | a settled choice — code, scope, direction, anything | `D-…` CLOSED (in force) |
| `Finding: <one line>` | a **settled fact / result**: nothing left to do | `F-…` STANDING |
| `Opens: <one line>` | an **open problem or question** — something to resolve | `F-…` OPEN |
| `Fixed: <one line>` | a problem found **and** resolved in this commit | `F-…` CLOSED |
| `Action: <one line>` | a to-do (pair with `Due:` / `Owner:`) | `A-…` OPEN |
| `Retires: <framing>` | an approach that is now dead — never re-propose | `R-…` STANDING |
| `Closes: <id>` | resolves an open finding / action | → CLOSED, `✓ closed by <sha>` |
| `Supersedes: <id>` | with a new `Decision:` — the old one is replaced; or `Supersedes: <old> by <new>` to fold a duplicate into its survivor | → SUPERSEDED, `⤳ superseded by` |
| `Refs: <id>, <id>` | this commit relates to existing entries | `↔ <sha> <subject>` backlink |
| `Ledger: none — <reason>` | explicit opt-out; reason ≥ 3 words | nothing |
| `Tidy: <summary>` | marks a `/ledger-tidy` pass (see below) | nothing |

**Modifiers** shape the entry trailer directly above them: `Due: YYYY-MM-DD`, `Owner: <who>`,
`Area: <tag>`, `Pin: yes` (keep it in the digest while in force), `Date: YYYY-MM-DD` (decided
earlier than committed — the entry says `(recorded <commit date>)`). Lore trailers (`Rejected:
<alt> | <why>`, `Constraint:`, `Directive:`, …) are recorded into that entry's body.

Ids are **content hashes** (`D-3fa9c1e`): the same on every clone and branch, so parallel
branches, worktrees, machines and cloud sessions never collide. Legacy sequential ids (`F-014`)
keep working everywhere. The `commit-msg` gate rejects a commit with no ledger trailer, a ledger
line outside the last paragraph (it would be silently lost), an id that names no entry, an id
where words belong (`Finding: F-1 …` — use `Refs:`), or a new entry that reads like a live one
without saying how they relate (`Refs:` / `Supersedes:` it — the planned-then-enacted duplicate).
Ids of another register the repo keeps (`EXTERNAL_IDS`, e.g. `C-012` in a `CONCERNS.md`) may be
cited freely.

## What to do when this skill fires

### A decision, finding, open question, action or retired approach comes up in conversation

1. **Grep the ledger first** (`LEDGER_PATH` in `.claude/ledger.conf`):
   `grep -n -B1 -A4 '<keyword>' <ledger>`. If it is already an entry — especially `retired`,
   `SUPERSEDED` or `CLOSED` — say so and stop. Re-opening a settled question costs more than
   reading it. A decision that **enacts** an earlier one is `Refs: D-…`, not a new `Decision:`.
2. Say it in one line and wait for approve / edit / decline:
   **"recording: `Decision: <one line>`"** (or `Opens:`, `Action: … Due: …`, `Retires:` …).
   Pick the trailer by the test: *is there anything left to do?* → `Opens:`/`Action:`; *just
   true now?* → `Finding:`; *found and fixed here?* → `Fixed:`; *replaces an earlier decision?*
   → `Decision:` + `Supersedes: D-…`.
3. Record it **now**, not "on the next commit" — in non-code work there may not be one:
   - if the change that enacts it is about to be committed, put the trailer on that commit;
   - otherwise make an empty commit that carries only the record (`--only` keeps anything the
     user has staged out of it):
     ```bash
     git commit --allow-empty --only -m "decide: <short subject>" \
       -m "<why, in a sentence or two — the commit body is the reasoning>" \
       -m "Decision: <one line>"
     ```
   The post-commit hook writes the entry and commits the ledger by itself. Never hand-write a
   trailer-born entry into `LEDGER.md`.
4. For a decision, put the **why** in the commit body (that is Lore's level 2). Write a section
   in `DECISIONS.md` too when the reasoning is bigger than a commit body: what was decided
   (quoting the ledger line), why, what was rejected, where it lives, what is still unvalidated.
   Append-only; a replaced section gains `**Superseded by:**`, never an edit.
5. A recurring `Directive:` about one area → propose a `.claude/rules/*.md` path-scoped rule.

### "note that …" / "remember that …"

Run `/ledger-note <text>` — a `note` (observation) or `thought` (thinking aloud, visibly *not*
a decision), written straight to the ledger and committed on its own.

### "where did we land on …" / "what's open" / "is this still current"

Answer from the injected digest and `grep` on the ledger. If the digest looks wrong or stale
versus `git log`, say so — do not silently work around it.

### A commit was rejected by the ledger gate

That is the system working. Read the reason, fix the trailer, re-commit. `Ledger: none — <reason>`
is for changes that genuinely record nothing (a reformat, a lockfile bump). Never add a `Refs:`
just to get past the gate. `--no-verify` only when the user asks.

### The digest starts with `LEDGER UPGRADE AVAILABLE`

Say it in one line and run `/ledger-init --upgrade` before the first commit of the session,
unless the user declines.

### The digest's housekeeping section reports something

- *hooks activated* — tell the user once that this clone's ledger git hooks were switched on.
- *stale rule* — a `.claude/rules/*.md` cites a closed finding or superseded decision; update or
  delete it (it is telling every session something untrue).
- *ledger lint* — a malformed or duplicate entry header; fix it by hand.
- *over the digest cap* — too many open items to show; that makes a tidy due.
- *Not shared* — ledger records that exist where this session cannot see them or others cannot
  see them: unpushed on this branch, on the upstream but not pulled (as of the last fetch), on
  another local branch or worktree, or unpushed on another machine (from the private index). Say
  it in one line when it matters to the task — decisions a collaborator or another machine
  cannot see, or work to merge before relying on the ledger. **Never push, pull or merge on
  your own**: offer it; those are the user's calls.
- *Tidy due* — the volume of work since the last tidy (new entries, merges, commits) has passed
  the threshold over enough days. Offer `/ledger-tidy` **once**, at a natural pause — the start
  of a session or the end of a chunk, never mid-task — with the reason from the digest in one
  line. If the user declines, drop it for the session.

### "tidy the ledger" / "clean up the open list" / "compress the ledger"

Run `/ledger-tidy`: it reports candidates (open items that read as settled, overdue or aging
items, near-duplicates and possible contradictions, empty entries, stale rules, other files that
keep their own lists), you propose in batches, the user approves, and one commit applies it
with a `Tidy:` trailer. It never deletes an entry — compression means fewer **live** entries,
not a second file.

### A repo with no ledger, about to get its first commit

Run `/ledger-init` **before** that commit, in one line: *"no ledger here yet; setting one up
first"*. The commit is the capture mechanism — a commit made without one is the entry that is lost.

### Cross-repo questions

Run `/ledger-status` and report per repo: open and overdue items, recent decisions, and the flags
(`N commits since last entry` = capture is lapsing; `⚠ triage`; `ledger uncommitted`).

## Dating honesty (non-negotiable)

A date is **bare** only if the entry was written live on that date. A reconstructed entry is
tagged `(recorded …)`, `(from <sha>)` or `(backfilled)`. Never put a bare date on a reconstructed
entry — inventing a tidy history is the exact failure this system exists to prevent. `Date:` on a
trailer produces the `(recorded …)` form automatically.

## Backfill (when `/ledger-init` runs on an existing repo)

Assess commit count, age, how rich the messages are, and whether decision-style trailers or ADR /
`DECISIONS*` / "retired" files already exist. Recommend **none** (young or scratch), **light**
(usual: scan the last ~100 messages and ADR files, propose entries) or **aggressive** (large
decision-heavy history: `git log -S` over key symbols plus a full scan). Everything proposed,
tagged `(backfilled)` / `(from <sha>)`, evidence pointing at **tracked** files only.

## Files in this skill

- `install.sh` — install / upgrade a repo; `--global-only` for commands, index, session hook
- `bin/ledger-status.sh` — the cross-repo dashboard · `bin/ledger-session.sh` — user-level hook
- `templates/` — `LEDGER.md`, `DECISIONS.md`, `ledger.conf`, `hooks/` (digest, sync, merge
  driver, rollup, index push, activate, parser), `githooks/` (commit-msg, post-commit), `rules/`
- `lib/common.sh` — shell helpers (copied into each repo as `_ledger_lib.sh`)
- `commands/` — `/ledger-init`, `/ledger-status`, `/ledger-note`, `/ledger-tidy`, `/ledger-setup`
- `reference/entry-format.md` — the entry schema · `reference/lore-paper.md` — the paper
- `tests/` — `bash tests/run_tests.sh` (end to end) · `python3 tests/test_merge.py`
