## Project ledger (living-ledger)

This repository keeps a ledger of decisions, findings, open questions and retired approaches in
`LEDGER.md`, generated from git commit trailers (the Lore protocol).

- **Before changing code in an area you do not know**, run `.claude/hooks/ledger context <path>`:
  it lists the directives, constraints and rejected alternatives recorded for that path.
- **Do not re-propose** anything under `.claude/hooks/ledger retired`.
- **Every commit carries a ledger trailer** in its last paragraph — `Decision:`, `Finding:`,
  `Opens:`, `Fixed:`, `Action:`, `Retires:`, `Closes: <id>`, `Supersedes: <id>`, `Refs: <id>` —
  or `Ledger: none — <reason>`. Name the alternative you rejected (`Rejected: <alt> | <why>`)
  and leave a `Directive:` when code is deliberately unusual. The `commit-msg` hook checks.
