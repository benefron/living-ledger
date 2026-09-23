---
description: Install or upgrade the living ledger in this repo (scaffold, hooks, cross-repo registration)
argument-hint: "[path] [--upgrade] [--backfill none|light|aggressive]"
---

# /ledger-init

Set up (or upgrade) the **living ledger** in a repository. Invoke the `living-ledger` skill first
if it is not already active. Arguments: `$ARGUMENTS`. The installer is
`~/.claude/skills/living-ledger/install.sh` (or `$LL_SKILL_DIR/install.sh`).

**No repo is worked in without a ledger**: in a repo with no `LEDGER.md`, run this *before the
first commit* — the commit is the capture mechanism.

## `--upgrade` (the digest said `LEDGER UPGRADE AVAILABLE`)

1. `install.sh "<repo>" --upgrade` — it upgrades in place, derives any trailers the history holds
   that the ledger has not recorded, and commits it all as one
   `chore: upgrade living ledger to template vN` commit (`Ledger: none`). It never rewrites or
   renumbers entries, keeps hand-set `ledger.conf` keys, and moves a v3 `core.hooksPath` setup to
   per-clone hook shims (so Git LFS & co. run again).
2. **From v1–v3, offer a first `/ledger-tidy`.** Before v4, every `Finding:` was created OPEN, so
   the open list is full of settled facts, and nothing was ever folded; a never-tidied ledger
   shows as due right away. The tidy report lists exactly what to review.
3. **Offer recovery of dropped trailers** if the repo was on v1–v3: the old parser silently
   dropped any trailer paragraph with a wrapped line. Measure it without touching the repo:
   ```bash
   V="$(mktemp)"; cp <ledger> "$V"
   FIRST="$(git log --reverse --format=%h -- <ledger> | head -1)"
   LL_SYNC_FROM="$FIRST" LL_LEDGER_FILE="$V" LL_DECISIONS_FILE= .claude/hooks/ledger-sync.sh
   diff <(grep '^## ' <ledger>) <(grep '^## ' "$V")
   ```
   If the user wants them, re-run `install.sh "<repo>" --upgrade --seed <that commit>`: the floor
   moves back and the sync records them at their original dates, in date order (dedup keeps
   existing entries single). Point out any that restate an entry recorded later — the next tidy
   folds them.

## Fresh install

1. **Locate the repo** (`git rev-parse --show-toplevel`); not a git repo → offer `git init`, stop.
2. **Detect prior state.** An existing `LEDGER.md` (`.claude/ledger.conf`, else `docs_root/`,
   `docs/`, root) is adopted — its entries are never touched. Look for **competing registers**
   (`RETIRED_FRAMINGS.md`, `CONCERNS.md`, `DECISIONS*`, `docs/adr/`, status/handoff docs that
   list decisions): propose folding them in via backfill, or replacing their lists with a pointer
   to the ledger, so the repo has one register — not two that drift apart.
3. **Ledger location** (fresh only): `docs_root/LEDGER.md` if `docs_root/` exists, else
   `docs/LEDGER.md` if `docs/` exists, else `LEDGER.md`. Confirm in one line.
4. **Visibility.** If the remote is public, say so: the ledger, `DECISIONS.md` *and every commit
   trailer* are public. Personal or strategic reasoning (a job search, a negotiation) belongs in a
   private repo. The installer warns too; let the user choose before anything is committed.
5. **Automation that commits** (a pipeline, a cron job, a bot): the installer adds any subject it
   sees repeated ≥ 5 times without trailers to `EXEMPT_SUBJECTS` in `.claude/ledger.conf`. Check
   the list with the user — a pipeline whose commit is rejected stops.
6. **Backfill depth** — `--backfill` if given, otherwise assess and recommend none / light /
   aggressive (see the skill). Wait for the pick.
7. **Run** `install.sh "<repo>" --ledger-path "<rel>"`. It writes `.claude/ledger.conf` (with the
   committed `SYNC_FROM` floor), `LEDGER.md` + `DECISIONS.md` if absent, `.claude/hooks/`, the
   committed git hooks in `.githooks/` plus per-clone shims, `merge=ledger` in `.gitattributes`,
   the `SessionStart`/`SessionEnd` hooks in `.claude/settings.json`, `.claude/rules/README.md`, and
   registers the repo in `~/.claude/ledger/`.
8. **Commit it**: `chore: install the living ledger` with
   `Decision: this repo keeps a living ledger at <path>; every commit carries a ledger trailer`.
9. **Backfill** (unless none): propose entries in the `recording: …` form; approved ones go under
   `<!-- ENTRIES_START -->` with `(backfilled)` / `(from <sha>)` dates — never bare — and evidence
   pointing at tracked files. Commit: `docs: backfill the living ledger`, `Ledger: none — backfill`.
10. **Tell the user how commits work now**, in three lines: every commit carries a trailer in its
    last paragraph (the table in the skill); `Ledger: none — <reason>` is the opt-out and
    `--no-verify` the escape hatch; the ledger syncs and commits itself after every commit.
