---
description: Record something in this repo's ledger right now — a note, thought, decision, open question or action — with no code change needed
argument-hint: "[decision|finding|opens|action|retires|note|thought] <text>"
---

# /ledger-note

Record `$ARGUMENTS` in this repo's ledger **now**. Invoke the `living-ledger` skill first if it is
not active. No ledger here → tell the user to run `/ledger-init` first.

## 1. Pick the kind

From the first word of the arguments if it names one, else from how the user framed it:
`decision` · `finding` (a settled fact) · `opens` (an open problem/question) · `action` (a to-do;
ask for a due date if one was implied) · `retires` · `note` (an observation) · `thought`
(thinking aloud — visibly *not* a decision). Unsure between note and thought → `thought`.
Grep the ledger first; if it is already there, say so and stop.

## 2a. decision / finding / opens / action / retires → an empty commit

The trailer is the record, so it goes through git like any other:

```bash
git commit --allow-empty --only -m "<kind>: <short subject>" \
  -m "<one or two sentences of context, if the user gave any>" \
  -m "<Decision|Finding|Opens|Action|Retires>: <the text>
Due: <YYYY-MM-DD, only if there is one>"
```

`--only` keeps whatever the user has staged out of it. The post-commit hook writes the entry and
commits the ledger. Confirm with the new id (`grep` the ledger for the text).

## 2b. note / thought → written directly

1. Ledger path: `LEDGER_PATH` in `.claude/ledger.conf`.
2. Id: `python3 .claude/hooks/_ledger_parse.py id N "<the text>"` (e.g. `N-4c1d2e9`).
3. Insert directly under `<!-- ENTRIES_START -->` (the date is bare — this is written live):
   ```
   ## N-xxxxxxx · STANDING · <note|thought> · - · <today YYYY-MM-DD>
   <the text>
   → <pointer, if the user gave one>
   ```
   Add a `· Pinned` line only if the user wants it kept in every session's digest (a pinned
   status note goes stale — prefer a dated one).
4. Commit only the ledger:
   `git commit -m "docs(ledger): note <short>" -m "Ledger: none — note written directly to the ledger" -- <ledger path>`
