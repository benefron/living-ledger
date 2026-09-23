---
description: Tidy this repo's ledger — triage open items, fold duplicates, settle contradictions, fix stale rules — so the digest stays true
argument-hint: "[--report-only]"
---

# /ledger-tidy

A ledger only helps while its digest is true. Work adds entries faster than anyone curates them:
facts left open, the same decision recorded when planned and again when enacted, a rule citing a
finding closed weeks ago. A tidy is a short, user-approved review that folds all of that back.
It never deletes an entry and never rewrites one's meaning — it changes statuses, links
duplicates to their survivor, and records itself.

The session digest says **Tidy due** when the volume of work since the last tidy — new entries,
merges (3 each), commits (1 per 5) — has passed `TIDY_VOLUME` (25) over at least `TIDY_MIN_DAYS`
(7), or three times that volume in any span, or the open list outgrew the digest. Offer it once,
at a natural pause; if the user declines, don't raise it again this session.

## 1. Report

```bash
python3 .claude/hooks/_ledger_parse.py tidy-report <ledger> "$(git rev-parse --show-toplevel)"
```

It lists candidates, each with the reason it was flagged: open items that read as settled,
overdue or aging items, similar entries (duplicate, refinement or contradiction), empty entries,
long-pinned entries, recent decisions with no written reasoning, stale rules, lint, and other
files in the repo that keep their own lists (retired framings, concerns, status docs). These are
heuristics: read each entry (`grep -n -A6 '^## <id> '`) and, where needed, its commit
(`git show <sha>`) before proposing anything. `--report-only`: show the report and stop.

## 2. Propose — in batches, one table per section

| id | entry (short) | proposal | why |
|---|---|---|---|

Proposals, and how each is applied:

| Proposal | Applied as |
|---|---|
| resolved | `Closes: F-…` trailer on the tidy commit (leaves `✓ closed by <sha>`) |
| a settled fact, not a problem | hand edit: `OPEN` → `STANDING` in its header, plus a body line `· tidied <date>: a settled result, not an open problem` |
| duplicate of a newer entry | `Supersedes: D-old by D-new` (the old one gains `⤳ superseded by D-new`) |
| contradiction | ask the user which holds; the loser gets `Supersedes: … by …` — or, if the question is genuinely open again, a new `Opens:` |
| overdue | the user picks: `Closes:`, a new `Due:` (hand-edit its `· Due:` line), or drop (`Supersedes: … by` the reason's entry, or `STANDING` with a tidied line) |
| empty / id-only entry | `Supersedes: F-junk by F-real`, or reword by hand if the commit shows what it meant |
| pinned too long | keep, or delete its `· Pinned` line |
| no written reasoning | offer a `DECISIONS.md` section (the skill's template); "self-evident" is a fine answer |
| stale rule | update or delete the file under `.claude/rules/` |
| other registers | bring them in line with the ledger, or replace their lists with a pointer to it |

Wait for approve / edit / decline on each batch. Never apply anything unapproved.

## 3. Apply — one commit

Hand edits (status flips, tidied lines, unpins, rules, DECISIONS sections) go into the working
tree; relations go into the trailers. Then:

```bash
git add <ledger> <decisions> .claude/rules
git commit -m "chore(ledger): tidy" \
  -m "<one or two sentences: what the pass found>" \
  -m "Closes: F-…, A-…
Supersedes: D-… by D-…
Tidy: <n> closed, <n> settled, <n> duplicates folded, <n> rules fixed"
```

`Tidy:` is what the next "tidy due" check counts from; every tidy commit carries it (even when
nothing but hand edits changed). The post-commit hook applies the `Closes:`/`Supersedes:` lines
and commits the ledger. Report the before/after: open count, live entries, digest size.

## Compression, and why there is no archive

A tidy is the compression: it shrinks what is **live** — what the digest shows and a session
has to weigh — without moving history out of the one file that grep, the sync's dedup and the
merge driver all read. Dead entries cost nothing: the digest is bounded and never shows them.
