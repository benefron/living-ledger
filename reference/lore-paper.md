# Lore — the protocol this builds on, and how living-ledger compares

**Ivan Stetsenko, "Lore: Repurposing Git Commit Messages as a Structured Knowledge Protocol for
AI Coding Agents."** arXiv:2603.15566 [cs.SE], March 2026. <https://arxiv.org/abs/2603.15566>

What follows summarises the paper in our own words, with a few short quotes, and then says
plainly where living-ledger follows it, where it extends it, and where it departs from it and why.

## The paper in brief

- **The problem — the "Decision Shadow".** A commit keeps the diff and throws away the reasoning:
  the constraints, the alternatives weighed and rejected, the confidence, the known gaps. It
  accumulates into code whose rationale is lost. AI agents make it urgent twice over: they are
  now the main *readers* of history (reconstructing intent from terse messages) and its main
  *writers* (producing messages that merely restate the diff).
- **The proposal — the "Lore atom".** Treat each commit as the smallest self-contained record of
  a decision, bound to the change that enacted it. Four properties: *atomic binding* (it cannot
  drift from the code — commit and message are one immutable object), *temporal immutability*
  (an append-only log), *universal availability* (every git repo already has the channel), and
  *natural granularity* (commits are already scoped to a unit of work).
- **The format — native git trailers**, all optional and extensible: `Constraint:`,
  `Rejected: <alternative> | <reason>`, `Confidence:`, `Scope-risk:`, `Reversibility:`,
  `Directive:`, `Tested:`, `Not-tested:`, `Related:`. The first line states *why*, not what.
- **The consumption model** — an agent discovers the protocol, *harvests constraints* for a path
  before editing it, *filters anti-patterns* using `Rejected:`, *absorbs directives* left for
  future modifiers, *reasons about staleness*, and *serialises its own context* into its commit.
- **The architecture** — "exactly two layers": the trailer format, and an optional CLI
  (`lore context|constraints|rejected|directives|coverage <path>`, `lore stale`,
  `lore commit`, `lore validate`). No servers, no index files, no databases.
- **Honest limits the paper names** — value depends on disciplined adoption; nothing recovers
  what was never written down; the format makes quality *auditable*, not guaranteed; ADRs
  remain better for cross-cutting architectural decisions. It proposes, but has not run, a
  two-team, six-month comparison.

## Where living-ledger follows Lore

| Lore | living-ledger |
|---|---|
| The commit is the unit of knowledge; trailers carry it | Same. `LEDGER.md` is *derived* from `git log` and can be rebuilt from it |
| `Constraint:` `Rejected:` `Directive:` `Confidence:` `Scope-risk:` `Reversibility:` `Tested:` `Not-tested:` `Related:` | Accepted verbatim and recorded on the entry they sit under — a living-ledger repo is a valid Lore repo |
| `lore context / constraints / rejected / directives <path>` | `.claude/hooks/ledger context\|constraints\|rejected\|directives <path>` — any agent, any shell |
| Constraint harvest before editing | …and **delivered automatically**: each commit's `Directive:`/`Constraint:`/`Rejected:` becomes a Claude Code path-scoped rule that loads when Claude reads a file that commit touched |
| Anti-pattern filtering via `Rejected:` | …and **enforced**: the commit gate refuses a new `Decision:` that re-adopts a rejected alternative or a retired framing, unless the commit supersedes it on purpose |
| `lore stale` | `ledger stale` — directives/constraints whose files changed a lot since; also a tidy-report section |
| `lore validate` | `ledger validate` — the gate's rules over recent history — **and** the gate itself, on every commit |
| Agent-first; zero special support | The git hooks and the `ledger` CLI work for any agent or person; the digest, rules and skill are Claude Code's extras |

## Where living-ledger extends it

- **Project state, not only rationale.** Lore records *why a change looks the way it does*.
  A live project also needs *what is open, what is settled, what is dead, what is due*:
  `Decision:` `Finding:` `Opens:` `Fixed:` `Action:` `Retires:`, lifecycle trailers (`Closes:`,
  `Supersedes:`, `Refs:`), and `Due:`/`Owner:`/`Pin:`. Those need **ids** — content hashes, so
  branches, machines and parallel agents never collide.
- **Push, not only pull.** Lore waits to be queried. The ledger hands every session a bounded
  digest (open, overdue, pinned, recent, retired) — the paper's context-window objection turned
  around: a few thousand tokens that are always relevant.
- **Enforcement.** Every commit relates to the ledger or says why not (`Ledger: none — …`).
  In real use the optional trailers were rare: in five repositories, between 0 and 22 commits
  each — out of 110 to 550 — carried any `Directive:`/`Constraint:`/`Rejected:` at all. Making
  them *do* something (rules, the gate, `ledger context`) is how v4 answers that.
- **Decisions that change no code.** Lore binds knowledge to "the code change that enacted it".
  A direction, a scope cut or a deadline has no diff; here it is an empty commit, dated and
  merged like any other.
- **Across repositories and machines** — a private cross-repo index, per-machine "not shared
  yet" reporting, and an entry-wise merge driver.
- **Curation** — `/ledger-tidy`, because a register drifts: settled facts left open, the same
  decision recorded when planned and again when enacted.

## Where it departs, and why

- **An index file.** Lore insists on none. Statuses change *after* the commit (a later
  `Closes:` resolves an earlier finding), so a current view has to be computed somewhere; a
  session-start digest needs it pre-digested and bounded. `LEDGER.md` is that computation,
  committed so humans can read it on GitHub — and regenerated from history, never the source.
- **A different first line.** Lore asks the subject to state intent. We leave subjects to the
  project's own convention (often Conventional Commits) and put intent in the body and trailers.
- **Not yet adopted** — `lore coverage` (a `Tested:`/`Not-tested:` map per path: `Not-tested:`
  shows in `ledger context`, a full map does not exist yet), an interactive `lore commit`
  builder (Claude writes the message; `/ledger-note` covers records without code), and the
  paper's two-team validation study. The six-repository audit behind v4 is field evidence of a
  different kind: what breaks in daily use, not a controlled comparison.

## Short quotes worth citing

- the commit as *"the atomic unit of institutional knowledge in a software project"*
- the commit and its message *"cannot drift out of sync"*
- *"zero special agent support is required"* — only a shell and text output
- *"No context window expansion recovers information never written down"*
