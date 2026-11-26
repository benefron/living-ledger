# Capture Nudge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect conversations that explore or settle decisions, measure silently whether a ledger record followed, and (once switched on at tidy) have the session suggest recording one.

**Architecture:** One new `UserPromptSubmit` hook (`ledger-capture.sh` → `_ledger_parse.py capture-hook`) scores each user message against a small cue lexicon and logs to `<git-common-dir>/ledger-capture/log.tsv`. A lazy audit, run by the digest and by `tidy-report`, reads the transcripts of ended sessions (both sides) and logs what the message hook cannot see. `tidy-report` gains a plain-words "Capture" section that proposes switching `CAPTURE=measure` → `nudge`. All code goes in `_ledger_parse.py` beside the recall code it mirrors (the file's established pattern; no new module, so no install or import changes).

**Tech Stack:** bash hooks, Python 3 stdlib, git, the offline bash harness `tests/run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-11-18-capture-nudge-design.md` (approved 2026-11-24; decisions D-a9e7ae1, D-a6a9756)

## Global Constraints

- Hooks run through `bash`; files written with LF; git output and stdin/stdout read as UTF-8 (D-8db1c00, D-4a63728).
- No model call, no network, anywhere. Hook budget about 50 ms.
- Nothing is written outside the git dir: state lives under `git rev-parse --git-common-dir` in `ledger-capture/`, never committed (F-266bd4e). Reading never writes the working tree.
- The log holds cue words and the transcript path, **never prompt text**. Sample text is read back from the transcript at report time.
- "A record followed" = a commit with a `Decision`/`Finding`/`Opens`/`Fixed`/`Action`/`Retires` trailer (the `KINDS` keys), found with the shared `trailer_lines()`; never a second regex (D-38e1459). `Closes`/`Supersedes`/`Refs`/`Tidy` do not count.
- Headless runs (`ll_interactive` false) and `CAPTURE=off` produce no output and no log rows.
- Defaults: `CAPTURE=measure`, `CAPTURE_MIN=2`, `CAPTURE_GAP=10` (prompts), grace after a session's last prompt `CAPTURE_GRACE=900` s, report needs 30 hits **or** 10 sessions, proposes `nudge` at ≥ 30% uncovered.
- Template version becomes **12**: every `ledger-template-version:` stamp, `LL_TEMPLATE_VERSION` in `install.sh`, and the hardcoded `11`s in `tests/run_tests.sh`.
- Tests must not use `grep … | grep -q` where the first grep can emit more than one buffer (the pipefail race fixed in d514003). Use a single `grep -q`, or `ghas`.
- Every commit carries a ledger trailer. Tasks below use `Refs: D-a9e7ae1` (they enact that decision). The gate rejects a commit without one.
- Not pushed to `origin` until the owner says so.

## Review Focus

Spec-implied failure modes no happy-path test would hit, each pinned by a test in the task that owns it:

1. A huge (200 KB) or malformed-stdin prompt: hook stays silent, exits 0, finishes fast (Task 2).
2. Hook JSON with no `session_id`: logged under `-`, never nudges, no crash (Task 2).
3. A transcript that is missing, unreadable, mid-write (partial last line) or over the size cap: session skipped, never an error, no audit row (Task 4).
4. A record commit made in the **same second** as the hit counts as covered (git dates have 1 s resolution; the log has 0.1 s) (Task 3).
5. Log rows from before the last `CAPTURE=` change in `ledger.conf` are excluded from the report, as recall excludes rows before an `RECALL_MIN=` change (Task 5).

---

## File Structure

| File | Responsibility |
|---|---|
| `templates/hooks/_ledger_parse.py` | All capture logic, in one section placed after `cmd_recall_stats` and before `main()`; `main()` dispatch gains `capture-hook`, `capture-stats`, `capture-digest` |
| `templates/hooks/ledger-capture.sh` (new) | Thin wrapper, a copy of `ledger-recall.sh` calling `capture-hook` |
| `templates/hooks/digest.sh` | Calls `capture-digest`; adds its line to `NOTES` |
| `templates/ledger.conf` | Documents `CAPTURE`, `CAPTURE_MIN`, `CAPTURE_GAP` (commented, defaults shown) |
| `install.sh` | Copies the new hook, adds it to `LL_EXEC_FILES`, registers it under `UserPromptSubmit`, `LL_TEMPLATE_VERSION=12` |
| `commands/ledger-tidy.md` | One proposals-table row for the capture mode |
| `tests/run_tests.sh` | New section `13l` before `14.`; hardcoded `11` → `12` |
| `CHANGELOG.md`, `SKILL.md` | v12 entry; one paragraph |

Test helper used throughout, defined once at the top of section 13l (Task 1):

```bash
PYC() { PYTHONDONTWRITEBYTECODE=1 python3 -c "import sys; sys.path.insert(0,'$SKILL/templates/hooks'); import _ledger_parse as p; $1"; }
```

---

### Task 1: Settings and the cue scorer

**Files:**
- Modify: `templates/hooks/_ledger_parse.py` (new section after `cmd_recall_stats`)
- Test: `tests/run_tests.sh` (new section `13l`, before `echo "14. the user-level session hook"`)

**Interfaces:**
- Produces:
  - `CAPTURE_CUES: dict[str, tuple[str, ...]]` with families `'direction'`, `'decision'`, `'open'` (lowercase phrases). Must include at least: direction `should we`, `what if`, `instead of`, `alternatively`, `which approach`, `trade-off`; decision `let's go with`, `we decided`, `scrap that`, `lock this in`, `that's dead`, `go with`; open `not sure`, `open question`, `do we need`, `how should we`.
  - `capture_settings(root: str) -> tuple[str, int, int]` → `(mode, min_score, gap)`; `mode` ∈ `'measure' | 'nudge' | 'off'`, anything unset or unrecognised → `'measure'`.
  - `capture_dir(root: str) -> str` → `<git-common-dir>/ledger-capture` (same shape as `recall_dir`).
  - `capture_countable(prompt: str) -> bool` → False for slash commands (`/…`), messages starting `<`, fewer than 4 words.
  - `capture_score(prompt: str) -> tuple[int, list[str]]` → `(score, cues)`: distinct cue phrases matched (case-insensitive, substring on the lowercased message); a `decision`-family cue counts 2; `(0, [])` when not countable.

- [ ] **Step 1: Write the failing tests** (section `13l`, header `echo "13l. the capture nudge: scoring, hook, audit, report"`, then the `PYC` helper):

```bash
check "capture: a direction + an open cue score 2+"   "PYC \"assert p.capture_score('should we use option a instead of b?')[0] >= 2\""
check "capture: one decision cue counts double"        "PYC \"assert p.capture_score(\\\"ok let's go with the second one\\\")[0] >= 2\""
check "capture: small talk scores 0"                   "PYC \"assert p.capture_score('ok that sounds good, please run it again now')[0] == 0\""
check "capture: slash, pasted and short are not countable" "PYC \"assert not any(p.capture_countable(s) for s in ['/ledger-tidy should we', '<pasted_content>should we</pasted_content>', 'should we go'])\""
check "capture: mode defaults to measure, unknown too" "PYC \"import tempfile,os; d=tempfile.mkdtemp(); os.makedirs(d+'/.claude'); open(d+'/.claude/ledger.conf','w').write('CAPTURE=bogus\\n'); assert p.capture_settings(d)[0]=='measure'\""
```

- [ ] **Step 2: Run to verify they fail**: `bash tests/run_tests.sh 2>&1 | grep -A8 "^13l"` → the five checks FAIL (`AttributeError: module … has no attribute 'capture_score'`).
- [ ] **Step 3: Implement** the interfaces above in `_ledger_parse.py`. `capture_settings` reads `CAPTURE`, `CAPTURE_MIN` (int, default 2), `CAPTURE_GAP` (int, default 10) with `_conf`, tolerating quotes and bad numbers as `recall_settings` does. `capture_dir` mirrors `recall_dir`.
- [ ] **Step 4: Run to verify they pass**: same command → `13l` checks `ok`; the whole suite still `0 failed`.
- [ ] **Step 5: Commit**: `git add templates/hooks/_ledger_parse.py tests/run_tests.sh && git commit` with subject `feat: capture scoring — cue lexicon, settings, countable messages` and trailer `Refs: D-a9e7ae1`.

---

### Task 2: The hook, its log, its wiring, template v12

**Files:**
- Create: `templates/hooks/ledger-capture.sh`
- Modify: `_ledger_parse.py` (hook + log refactor + `main()` dispatch), `install.sh`, `templates/ledger.conf`, every `ledger-template-version: 11` stamp, `tests/run_tests.sh`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `_append_log(d: str, rows: list[tuple]) -> None` — the body of today's `_log_recall` (mkdir, append TSV, rotate above 2,000,000 bytes keeping the newest half) taking the directory; `_log_recall(root, rows)` becomes a one-line caller. Recall tests must still pass unchanged.
  - Log row format, tab-separated, `(epoch: float 0.1 s, session: str, transcript: str, kind: str, score: str, detail: str)`. Kinds: `prompt` (detail `words=N`), `hit` (detail = cues joined by `|`), `nudge`, and, from later tasks, `audit`, `told`. Session `-` when the hook JSON has none.
  - `cmd_capture_hook(argv: list[str]) -> str` — argv `[root]`, hook JSON on stdin; returns the `UserPromptSubmit` JSON string, or `''`.
  - Nudge text (exact first words, tests grep for them): `Ledger capture — this conversation looks like it is weighing directions or decisions.` followed by the guidance in the spec's Nudging paragraph.
  - `ledger-capture.sh`: stamped `ledger-template-version: 12`, gated by `ll_interactive`, `exec`s `capture-hook`.

- [ ] **Step 1: Write the failing tests** (continue section `13l`). Setup `CP="$(newrepo capture)"; installed "$CP"` (the repo needs a ledger; sync once with a `Decision:` commit as 13i does). Helper `CH <session> <prompt>` pipes `{"session_id":…,"prompt":…,"transcript_path":""}` into `$CP/.claude/hooks/ledger-capture.sh`, printing the hook's `additionalContext` or nothing. `LOG="$CP/.git/ledger-capture/log.tsv"`. Assertions:
  - `settings.json registers the capture hook` (`ledger-capture.sh` in `hooks.UserPromptSubmit`).
  - measure: decision-like prompt → `CH` output empty; `$LOG` has one `hit` and one `prompt` row; no row holds the prompt text (`! grep -q 'second one' "$LOG"`).
  - small talk → one `prompt` row, no `hit`; slash / `<…` / 3-word prompts → no rows.
  - `CAPTURE=nudge` (append to `$CP/.claude/ledger.conf`, leave uncommitted; assert `git status --porcelain` unchanged by the hook itself): first hit → output starts `Ledger capture —`; with `CAPTURE_GAP=2`, a second hit next prompt → silent, third prompt hit → nudges again.
  - nudge suppressed once a record commit exists after the session's first prompt (`commit "$CP" "x

Decision: use the second option"` then a hit → silent).
  - `CAPTURE=off`, and `CLAUDE_CODE_ENTRYPOINT=sdk-cli`, → silent and no new rows.
  - **Review Focus 1:** a 200 KB prompt (`should we ` repeated) and unparseable stdin (`echo '{{' | …`) → exit 0, empty output, under 2 s (`timeout 2`).
  - **Review Focus 2:** hook JSON with no `session_id` → rows logged with session `-`, output empty even in nudge mode.
  - nothing written outside `.git`: `git -C "$CP" status --porcelain` identical before and after a run of hits.
- [ ] **Step 2: Run to verify they fail**: `13l` hook checks FAIL (script missing).
- [ ] **Step 3: Implement.** (a) Extract `_append_log` and call it from `_log_recall`. (b) `cmd_capture_hook`: same skeleton as `cmd_recall_hook` — parse stdin, return `''` when mode is `off`, the ledger is missing, or the message is not countable; always log `prompt`; on score ≥ `min_score` log `hit`; in `nudge` mode with a real session id emit the nudge only if ≥ `gap` `prompt` rows of this session since its last `nudge` row, and no record commit since this session's first prompt (use `capture_covered` from Task 3 — stub it to `False` until then and wire it in Task 3 step 3). Log a `nudge` row when emitted. (c) Create `ledger-capture.sh` as a copy of `ledger-recall.sh` with the new script and mode name. (d) `install.sh`: `install -m 0755` the new file, append `.claude/hooks/ledger-capture.sh` to `LL_EXEC_FILES`, register under `UserPromptSubmit` with `has(up, None, "ledger-capture.sh")`, timeout 10, `LL_TEMPLATE_VERSION=12`; update the summary `say` line. (e) `templates/ledger.conf`: three commented lines documenting the keys and defaults. (f) Bump stamps: `grep -rlE 'ledger-template-version: 11' templates install.sh lib commands SKILL.md | xargs perl -pi -e 's/ledger-template-version: 11/ledger-template-version: 12/'`; in `tests/run_tests.sh` change every `ledger-template-version: 11` in the `perl -pi` lines (≈660, 675, 684) to `12`. (g) `main()`: add `'capture-hook': cmd_capture_hook`.
- [ ] **Step 4: Run to verify they pass**: full suite `0 failed`, including test 1's "every stamp is the version install.sh ships (v12)" and the 13i recall checks.
- [ ] **Step 5: Commit**: subject `feat: the capture hook, silent by default (template v12)`, trailer `Refs: D-a9e7ae1`.

---

### Task 3: Coverage and per-session grouping

**Files:**
- Modify: `_ledger_parse.py`, `tests/run_tests.sh`

**Interfaces:**
- Consumes: Task 2's log format.
- Produces:
  - `capture_covered(root: str, start: float, end: float) -> bool` — True if any non-merge commit reachable from any ref (`--all`) with committer time in `[floor(start), end]` has a trailer key in `KINDS`, read via `trailer_lines()`.
  - `capture_sessions(root: str) -> dict[str, dict]` — keyed by session id (excluding `-`), only rows since the last commit that changed a `^CAPTURE=` line in `.claude/ledger.conf` (as `recall_stats` does with `-G '^RECALL_MIN='`). Each value: `{'transcript': str, 'first': float, 'last': float, 'prompts': int, 'hits': list[tuple[float, str]] (epoch, cues), 'nudges': int, 'audit': tuple[int, int, bool] | None  # (decision_like, accepted, covered), 'told': bool}`.

- [ ] **Step 1: Write the failing tests** (via `PYC`, repo `$CP`, commits dated with `GIT_COMMITTER_DATE`):
  - decision-trailer commit inside the window → `True`; `Ledger: none` commit only → `False`; `Closes:`-only commit → `False`; commit outside the window → `False`.
  - **Review Focus 4:** hit logged at `T+0.4` with a record commit at second `T` → `capture_covered(root, T+0.4, T+60)` is `True`.
  - `capture_sessions` on a hand-written log (two sessions, one hit row, one `audit` row `detail='human=2;accepted=1;covered=0'`, one `told` row) returns the structure above.
- [ ] **Step 2: Run to verify they fail** (`no attribute 'capture_covered'`).
- [ ] **Step 3: Implement** both functions; `git log --all --no-merges --since=<epoch> --until=<epoch> --format=%B%x1e` with `trailer_lines`. Replace Task 2's `capture_covered` stub call in the hook; add the "record commit since this session's first prompt → no nudge" test to Task 2's assertions if not already green.
- [ ] **Step 4: Run to verify they pass**: full suite `0 failed`.
- [ ] **Step 5: Commit**: `feat: capture coverage — did a record commit follow`, `Refs: D-a9e7ae1`.

---

### Task 4: The session audit

**Files:**
- Modify: `_ledger_parse.py`, `tests/run_tests.sh`

**Interfaces:**
- Consumes: Tasks 2–3; existing `_transcript_turns(path) -> list[tuple[float, str, str]]` (`(epoch, 'human'|'agent', text)`).
- Produces:
  - `CAPTURE_PROPOSALS: tuple[str, ...]` — agent-side phrases: at least `which way`, `approve`, `my recommendation`, `want me to`, `say so and i'll`, `which approach`.
  - `CAPTURE_ACCEPTS: tuple[str, ...]` — human replies (whole message, ≤ 3 words, lowercased, punctuation stripped): at least `a`, `b`, `yes`, `ok`, `okay`, `approve`, `approved`, `go ahead`, `do it`, `sounds good`.
  - `decision_turns(turns: list[tuple[float, str, str]]) -> tuple[int, int]` — `(decision_like, accepted)`: human turns scoring ≥ 2 on `capture_score` (the scorer's `CAPTURE_MIN` default), and human accept-replies directly after an agent turn containing a proposal phrase.
  - `capture_audit(root: str, now: float | None = None, limit: int | None = None, max_bytes: int = 5_000_000) -> int` — for each session from `capture_sessions` with no `audit` row whose `last + CAPTURE_GRACE < now`: skip (no row, no error) if the transcript path is empty, missing, unreadable or larger than `max_bytes`; else append one `audit` row, detail `human=N;accepted=M;covered=0|1`, where covered = `capture_covered(root, first_turn_ts, last_turn_ts)`. Newest sessions first; stop after `limit`. Returns the number audited.

- [ ] **Step 1: Write the failing tests.** A synthetic transcript helper writes JSONL in the format `_transcript_turns` reads (`{"type":"assistant","timestamp":"2026-11-20T10:00:00Z","message":{"content":[{"type":"text","text":…}]}}` and `{"type":"user",…,"message":{"content":"a"}}`):
  - agent "Which way do you want to go? My recommendation is A." then human `a` → `(0, 1)`; human `a` with no proposal before → `(0, 0)`; human `yes please go ahead with it now` (> 3 words) → not accepted; human "let's go with option A instead of B" → `(1, 0)`.
  - `capture_audit`: a session ended > grace ago is audited once, a second call returns 0 (idempotent), an unended one returns 0; `covered=1` when a record commit lies in the transcript's own time window.
  - **Review Focus 3:** path missing, path empty string, a file whose last line is truncated JSON (still audits the good lines), and `max_bytes=10` → each returns 0 or audits without raising; no `audit` row for the skipped ones.
  - no prompt text in the log: `! grep -q '<a phrase from the transcript>' "$LOG"`.
- [ ] **Step 2: Run to verify they fail**.
- [ ] **Step 3: Implement** both functions and the two phrase tuples.
- [ ] **Step 4: Run to verify they pass**: full suite `0 failed`.
- [ ] **Step 5: Commit**: `feat: capture audit — read ended sessions for what the message hook misses`, `Refs: D-a9e7ae1`.

---

### Task 5: The tidy report and `capture-stats`

**Files:**
- Modify: `_ledger_parse.py` (`tidy_report`, `main`), `commands/ledger-tidy.md`, `tests/run_tests.sh`

**Interfaces:**
- Consumes: Tasks 3–4.
- Produces:
  - constants `CAPTURE_MIN_HITS = 30`, `CAPTURE_MIN_SESSIONS = 10`, `CAPTURE_UNCOVERED_SHARE = 0.30`.
  - `capture_report(root: str) -> list[str]` — report lines, `[]` when `CAPTURE=off` or nothing is logged. It first runs `capture_audit(root)` (all ended sessions). The text states, in plain words: messages counted, hits and share; sessions audited; of those with a hit or decision-like exchanges, how many had a record commit and how many did not; how many decision-like exchanges were bare acceptances and what share of all that is (the message hook's blind spot); up to five hit messages and three accepted proposals quoted from their transcripts; the sentence that a session with only a `/ledger-note` note or thought reads as uncovered; then one proposal line: fewer than `CAPTURE_MIN_HITS` hits **and** fewer than `CAPTURE_MIN_SESSIONS` such sessions → "keep measuring", saying how many more; otherwise uncovered share ≥ `CAPTURE_UNCOVERED_SHARE` → `set CAPTURE=nudge in .claude/ledger.conf` plus the instruction to record `Decision: capture nudge on — <the numbers>`; otherwise "leave it in measure (or raise CAPTURE_MIN)" with the reason.
  - `tidy_report` appends `## Capture (measuring)` (or `(nudging)` when the mode is `nudge`) after the recall section; `main()` dispatch gains `'capture-stats': lambda a: "\n".join(capture_report(a[0]))`.

- [ ] **Step 1: Write the failing tests** (`PYC`, with `p.CAPTURE_MIN_HITS=2; p.CAPTURE_MIN_SESSIONS=2` set inside the snippet; synthetic log rows and transcripts):
  - report with 1 hit → contains `keep measuring` and a count of how many more.
  - report with 3 hit sessions, 2 uncovered (≥ 30%) → contains `CAPTURE=nudge`; 3 hit sessions, all covered → contains `leave it`.
  - report quotes a hit message (its text appears; read from the transcript) and says the note-or-thought limitation.
  - the bare-acceptance share appears as a percentage.
  - **Review Focus 5:** rows older than a commit that changed the `CAPTURE=` line in `ledger.conf` are not counted (add rows, commit a `CAPTURE=` change, add one new row → the report counts one).
  - `python3 _ledger_parse.py tidy-report` output contains the `## Capture` heading; `capture-stats <root>` prints the same lines; a repo with `CAPTURE=off` has neither.
- [ ] **Step 2: Run to verify they fail**.
- [ ] **Step 3: Implement** `capture_report` (read samples with `_transcript_turns`, matching the human turn nearest each hit's epoch within 60 s), wire it into `tidy_report` and `main`; add the `capture mode` row to the proposals table in `commands/ledger-tidy.md` (applied as: set `CAPTURE=nudge` in `.claude/ledger.conf`, and a `Decision:` trailer with the numbers).
- [ ] **Step 4: Run to verify they pass**: full suite `0 failed`, including the existing tidy-report checks (13c), which must be unaffected when nothing is logged.
- [ ] **Step 5: Commit**: `feat: the tidy report says how often decisions went unrecorded`, `Refs: D-a9e7ae1`.

---

### Task 6: The digest line (nudge mode only)

**Files:**
- Modify: `_ledger_parse.py`, `templates/hooks/digest.sh`, `tests/run_tests.sh`

**Interfaces:**
- Consumes: Task 4.
- Produces:
  - `capture_digest_note(root: str) -> str` — `''` unless mode is `nudge`; else the most recently audited session with `decision_like + accepted > 0`, `covered` false and no `told` row → appends a `told` row and returns `Last session: N decision-like exchange(s), no record commit — ask whether to record them.` (N = decision_like + accepted, singular/plural handled).
  - `cmd_capture_digest(argv: list[str]) -> str` — argv `[root]`; returns `''` when mode is `off`; else runs `capture_audit(root, limit=3)` (also in `measure`, so the measurement does not depend on a tidy) and returns `capture_digest_note(root)`; `main()` dispatch `'capture-digest'`.
  - In `digest.sh`, before `[ -n "$DIGEST" ] || …`: `CAP="$(… python3 "$HERE/_ledger_parse.py" capture-digest "$REPO" 2>/dev/null || true)"` and, if non-empty, `NOTES="$NOTES\n- $CAP"` in the existing style.

- [ ] **Step 1: Write the failing tests** (installed repo, synthetic ended session with an accepted proposal and no record commit):
  - `measure`: `digest "$CP"` has no `Last session` line, **but** the log now has an `audit` row.
  - `nudge`: first `digest "$CP"` contains `Last session: 1 decision-like exchange`; the second does not; the log has exactly one `told` row.
  - a covered session (record commit in its window) → no line.
  - headless (`CLAUDE_CODE_ENTRYPOINT=sdk-cli`) digest → empty and no new rows.
  - a 6 MB transcript for an ended session → the digest returns in under 5 s (`timeout 5`) and writes no `audit` row.
- [ ] **Step 2: Run to verify they fail**.
- [ ] **Step 3: Implement** the two functions and the `digest.sh` call.
- [ ] **Step 4: Run to verify they pass**: full suite `0 failed`; existing digest checks (sections 8–10) unchanged.
- [ ] **Step 5: Commit**: `feat: the next session's digest says when decisions slipped past`, `Refs: D-a9e7ae1`.

---

### Task 7: Release v12, and this repo runs it

**Files:**
- Modify: `CHANGELOG.md`, `SKILL.md`, this repo's own `.claude/` (via the installer)

**Interfaces:** Consumes everything above.

- [ ] **Step 1: Write `## v12 — <today>` in `CHANGELOG.md`** in the existing style: what ships (capture hook in `measure`, the lazy audit, the tidy section, the nudge digest line, config keys), what upgrading does (adds the hook in `measure`, changes nothing visible), the `/ledger-note` limitation. One paragraph in `SKILL.md` naming `CAPTURE`, where the log lives, and that nothing is committed automatically.
- [ ] **Step 2: Upgrade this repo** with `bash install.sh . --upgrade --quiet`, then confirm `CAPTURE` is unset (so `measure`), `.claude/settings.json` registers `ledger-capture.sh`, and every stamp reads 12.
- [ ] **Step 3: Verify**: `bash tests/run_tests.sh` → `0 failed`; `python3 tests/test_merge.py` → `OK`; one real dry run: `echo '{"session_id":"s","prompt":"should we go with option a instead of b?"}' | bash .claude/hooks/ledger-capture.sh` prints nothing, and `.git/ledger-capture/log.tsv` has a `hit` row.
- [ ] **Step 4: Commit** (one commit for the release and the upgrade): subject `chore: template v12 — the capture nudge, measuring`, trailers `Decision: template v12 ships the capture nudge in measure mode; it is switched to nudge only at a tidy, from the report's numbers` and `Refs: F-5eb5445, D-a9e7ae1`. Do **not** `Closes:` F-5eb5445: it closes only after a nudged period shows the uncovered share fell (spec, "Resolving the finding").
- [ ] **Step 5: Stop and report** — do not push. Tell the owner what to do next: use the repo normally; at the next `/ledger-tidy` the Capture section appears.
