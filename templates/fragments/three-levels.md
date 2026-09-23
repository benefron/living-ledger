**Three levels of a decision.** A decision is captured at up to three levels, each for a different
reader, and the levels must agree:

| Level | Where | Reader | What it holds |
|---|---|---|---|
| 1. Fact | **this file**, via the `Decision:` trailer of the commit that enacted it | future sessions, the injected digest | one sentence, status, evidence pointer |
| 2. Reasoning | the **body of the commit** that carried the trailer, and **`__DECISIONS_PATH__`** when it needs more room — append-only, every section dated | you, collaborators | what was decided (quoting level 1), why — the numbers and the `F-`/`D-` ids, what was rejected and why, where it lives, what validation is still pending |
| 3. Audience | *only if this repo has an audience surface* — a deck script, a paper, the README's claims. `.claude/ledger.conf` names it under `AUDIENCE_SURFACE=` | that audience | the current state. Updated **on request**; nothing rebuilds it automatically, and it never rewrites history |

The order is fixed: the trailer goes on the commit → the post-commit hook writes level 1 → `ledger-sync.sh`
appends the dated fact to level 2's log → a human writes the reasoning above it. Level 3 moves only when
you ask for it.

A decision that exists at level 1 only is a verdict with no argument behind it. A decision that exists at
level 2 only is invisible to every future session. Both are incomplete.

**Level 2 is append-only and keeps its history.** A superseded decision is never deleted and never
edited: it gains a `**Superseded by:** <section / ledger id> · <date>` line, and the section that
replaces it opens with `**Supersedes:** …`. The corrections *are* the record.
