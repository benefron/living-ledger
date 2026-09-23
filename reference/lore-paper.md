# Lore — the pattern this skill implements

**Ivan Stetsenko, "Lore: Repurposing Git Commit Messages as a Structured Knowledge
Protocol for AI Coding Agents."** arXiv:2603.15566v1 [cs.SE], 16 March 2026.
<https://arxiv.org/abs/2603.15566>

Cite this when explaining that the living-ledger is an established method, not a
homegrown convention.

## The problem it names

The **Decision Shadow**: *"the unrecorded reasoning behind why the code looks the way it
does at any given point"* — the constraints, rejected alternatives, and forward-looking
context that a diff discards. Over time these accumulate into what the industry calls
legacy code. Both shifts that make it urgent are ours: agents are now primary code
*consumers* (reconstructing intent from code because the history says `refactor: clean up
utils`) and primary *producers* (writing commit messages that just re-summarise the diff).

## The proposal

*"A commit should not be a label on a diff. It should be the atomic unit of institutional
knowledge in a software project — the smallest self-contained record of a decision,
permanently and immutably bound to the code change that enacted it."* Stetsenko calls
this a **Lore atom**. Its four properties:

- **Atomic binding** — *"it cannot drift out of sync — the commit and its message are a
  single immutable object."* (Contrast: wikis, ADRs, chat threads.)
- **Temporal immutability** — an append-only log of decisions.
- **Universal availability** — every git project already has this channel; distribution
  (clone/fetch/pull) is already solved.
- **Natural granularity** — commits are already scoped to logical units of work.

## Format — native git trailers

| Trailer | Meaning |
|---|---|
| `Constraint:` | rule that shaped this decision and may still be active |
| `Rejected:` | alternative evaluated and dismissed, with the reason (`alt \| why`) |
| `Confidence:` | `low` / `medium` / `high` |
| `Scope-risk:` | blast radius: `narrow` / `moderate` / `wide` |
| `Reversibility:` | `clean` / `migration-needed` / `irreversible` |
| `Directive:` | forward-looking instruction to future modifiers |
| `Tested:` / `Not-tested:` | what was and was not verified |
| `Related:` | related commits by hash |

*"Every trailer is optional. The format is additive and extensible: unknown keys are
ignored."* The consumption model: **constraint harvest** before editing a file,
**anti-pattern filtering** from `Rejected:`, **directive absorption**, and a
`lore stale` command that *"surfaces constraints that may be outdated, enabling a
self-healing knowledge base."* *"Zero special agent support is required — only the
ability to run shell commands and read text output."*

## How the living-ledger maps onto Lore

| Lore | living-ledger |
|---|---|
| the commit message as the knowledge atom | the trailer is the record; `LEDGER.md` is derived from `git log` |
| `Rejected:` / `Constraint:` / `Directive:` … | recorded verbatim into the entry they sit under |
| decision reasoning in the commit | `Decision:` → `D-…`; the commit body is the reasoning (level 2) |
| `Directive:` to future modifiers | `.claude/rules/*.md` path-scoped rules |
| `lore stale` self-healing | `Closes:` / `Supersedes:` status changes; stale-rule and lint reports; the dashboard's lapse flag |
| `lore context <path>` query | `grep` the ledger; the area-ranked session digest; path-scoped rules |
| `lore validate` | the `commit-msg` gate (same trailer reader as the sync) |

The living-ledger adds vocabulary Lore does not have — `Finding:` / `Opens:` / `Fixed:` /
`Action:` / `Retires:` / `Supersedes:` and `Due:` / `Owner:` / `Pin:` — because it tracks the
*state* of a project (what is open, overdue, in force, dead), not only the rationale of changes.

## Where we deliberately diverge

Lore's architecture is *"exactly two layers"* — the trailer format and an optional CLI —
and explicitly *"No servers, no index files, no databases."* The living-ledger adds a
**materialised layer**: `LEDGER.md` plus the session-start digest. Reason: `SessionStart`
context injection needs a bounded, pre-digested artifact; grepping raw `git log` at every
session start is unbounded and slow. The trailer remains the source of truth
(`ledger-sync.sh` regenerates entries from git), so the added layer is a cache, not a
second register.

Lore is also explicit that it is **complementary to ADRs**, not a replacement — ADRs for
cross-cutting architectural decisions, trailers/ledger for implementation-level ones.

## Reported limitations (worth stating honestly)

- Depends on disciplined adoption; missing or poorly-formed trailers reduce utility.
- *"No context window expansion recovers information never written down"* — value is
  primarily inter-session and inter-agent.
- Structured format makes quality auditable but does not by itself solve trust
  (rubber-stamped low-quality atoms). Mitigation in Lore: a `lore validate` check.
