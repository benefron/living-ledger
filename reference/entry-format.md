# Ledger entry format

Every entry is one greppable block. The header line is machine-parsed by `_ledger_parse.py` —
keep it exact (`_ledger_parse.py lint <ledger>` reports any header that is not).

```
## <ID> · <STATUS> · <type> · <area|-> · <date>
<one line: what, and why it matters>
· <modifier or Lore line>            (optional, any number)
→ <evidence: commit sha, file:line>
↔ / ✓ / ⤳ <sha> <subject>            (appended later by Refs:/Closes:/Supersedes:)
```

The separator between header fields is ` · ` (space, U+00B7, space).

## Fields

| Field | Values |
|---|---|
| `ID` | prefix + content hash: `D-3fa9c1e` decision · `F-` finding · `A-` action · `R-` retired · `N-` note/thought. `sha1("<P>:<normalised text>")[:7]` — `_ledger_parse.py id F "<text>"` prints it. Legacy sequential ids (`F-014`) stay valid everywhere. |
| `STATUS` | `OPEN` · `CLOSED` · `SUPERSEDED` · `STANDING` |
| `type` | `decision` · `finding` · `action` · `retired` · `note` · `thought` |
| `area` | a workstream tag: `Area:` on the trailer, else the directory the commit touched (≤ 2 levels), else `-` |
| `date` | `YYYY-MM-DD`, optionally ` (recorded <date>)` / ` (from <sha>)` / ` (backfilled)` |

## What each trailer does

| Trailer | Creates / changes | type | status |
|---|---|---|---|
| `Decision: <line>` | `D-…` | `decision` | `CLOSED` — settled, in force until superseded |
| `Finding: <line>` | `F-…` | `finding` | `STANDING` — a settled fact; nothing to do |
| `Opens: <line>` | `F-…` (or `Opens: F-x <line>` to choose the id) | `finding` | `OPEN` |
| `Fixed: <line>` | `F-…` | `finding` | `CLOSED` — found and resolved in the same commit |
| `Action: <line>` | `A-…` | `action` | `OPEN` |
| `Retires: <framing>` | `R-…` | `retired` | `STANDING` |
| `Closes: <id>` | that entry `OPEN` → `CLOSED`, plus `✓ closed by <sha> <subject>` | | |
| `Supersedes: <id>` | that entry → `SUPERSEDED`, plus `⤳ superseded by <the commit's new decisions> in <sha>` | | |
| `Supersedes: <old> by <new>` | the same, naming the survivor — how a tidy folds a duplicate | | |
| `Tidy: <summary>` | nothing; marks a tidy pass, from which "tidy due" counts again | | |
| `Refs: <id>, …` | `↔ <sha> <subject>` on each; creates nothing | | |
| `Ledger: none — <reason>` | nothing; the reasoned opt-out (≥ 3 words) | | |

Modifiers — `Due: YYYY-MM-DD`, `Owner: <who>`, `Area: <tag>`, `Pin: yes`, `Date: YYYY-MM-DD` — and
Lore trailers (`Rejected:`, `Constraint:`, `Directive:`, `Confidence:`, `Scope-risk:`,
`Reversibility:`, `Tested:`, `Not-tested:`, `Related:`) belong to the entry trailer **directly
above them**; placed before the first entry trailer they apply to every entry of the commit. They
land in the body as `· Key: value` lines (`Pin: yes` as `· Pinned`).

Each `Closes:`/`Supersedes:`/`Refs:` is applied **once**: the sha it leaves on the entry marks it
done, so a re-scan never undoes a hand edit (re-opening an entry by hand sticks).

## Where trailers are read

Only from the **last paragraph(s)** of the message: walking back from the end, a paragraph counts
while its first line is `Key: value` and every other line is another `Key: value` or the
continuation of one (indented, or simply wrapped after a ledger/Lore key). Prose that mentions
"Decision:" mid-paragraph is never a trailer. The `commit-msg` gate uses the same reader, and
rejects a ledger line that sits outside that block instead of letting it be silently dropped.

## Status by type

| type | born | moves to |
|---|---|---|
| decision | `CLOSED` (in force) | `SUPERSEDED` via `Supersedes:` |
| finding (fact) | `STANDING` | `SUPERSEDED` if it turns out wrong |
| finding (problem) | `OPEN` | `CLOSED` via `Closes:` |
| action | `OPEN` | `CLOSED` via `Closes:` |
| retired | `STANDING` | — |
| note / thought | `STANDING` | — |

A rule in `.claude/rules/` is **stale** when it cites a `CLOSED` finding/action or any
`SUPERSEDED` entry; a rule citing an in-force decision is not.

## Dating honesty

- **bare** — written live on that date.
- **`(recorded <date>)`** — decided on the header date, entered later (`Date:` trailer), or copied
  from a document that already carried the date.
- **`(from <sha>)`** — recovered via `git log -S`; the commit that introduced the claim.
- **`(backfilled)`** — reconstructed, no better evidence; treat as approximate.

Never a bare date on a reconstructed entry.

## Levels 2 and 3

The ledger is level 1 — the fact. Level 2 — the reasoning — is the body of the commit that
carried the trailer (`git show <sha>`), plus `DECISIONS.md` (`DECISIONS_PATH`) when it needs more
room: append-only, every section dated and headed with the ledger id:

```
## D-3fa9c1e · <short title> · <YYYY-MM-DD>
**Supersedes:** D-8b1e0d2 · <date>      (only when it replaces an earlier decision)
**What was decided.**  <quotes the ledger entry verbatim>
**Why.**               <evidence: numbers, F-/D- ids>
**What was rejected.** <the alternative, and why it lost>
**Where it lives.**    <file:line / config key>
**Validation pending.** <what would falsify it, or "none — settled">
```

A superseded section is never deleted or edited — it gains `**Superseded by:** D-… · <date>`.
Between `<!-- DECISIONS_LOG_START -->` and `<!-- DECISIONS_LOG_END -->` the sync appends one row
per `Decision:`/`Retires:` automatically; do not hand-edit between the markers.

Level 3 is the repo's **audience surface** — a deck script, a paper, the README's claims — *only
if it has one*, named in `.claude/ledger.conf` as `AUDIENCE_SURFACE=`. Updated **on request**.

## Lifecycle

Nothing is deleted — the sync would restore a trailer-born entry anyway. A wrong entry is marked
`SUPERSEDED` with a pointer to what replaced it; git holds the history.

## Examples

```
## D-3fa9c1e · CLOSED · decision · src/encoder · 2026-09-09
use a single-writer queue for the encoder instead of a lock
· Rejected: fine-grained locks | deadlocked under the stress test
→ commit a1b2c3d
↔ 9f8e7d6 fix: honour the queue bound in the sweep

## A-51c07e2 · OPEN · action · hiring · 2026-09-12
send the take-home brief to both finalists
· Due: 2026-09-19
· Owner: sam
→ commit 4d5e6f7

## F-8b1e0d2 · CLOSED · finding · - · 2026-09-09
the cache is never invalidated after a deploy
→ commit 0a1b2c3
✓ closed by 7c8d9e0 fix: bust the cache on deploy

## R-0c4f7a1 · STANDING · retired · - · 2026-07-22 (from a04aacd)
"a nightly batch job is good enough" — replaced by streaming; batch is backfill only
```
