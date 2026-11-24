# Capture nudge — design

2026-11-18 · resolves the open finding F-5eb5445 ("capture still needs a commit — a decision nobody
states in a session never reaches the ledger") · status: **approved by the owner 2026-11-24**

## Intent

The ledger only learns what a commit tells it. A conversation that explores directions, weighs
options, settles a question or leaves one open produces nothing durable unless someone — in practice
Claude, prompted by the skill's trigger phrases — remembers to record it. Nothing today notices when
that does not happen: the "N commits since last entry" signal counts commits, so a purely
conversational decision is invisible to it.

The owner wants the session itself to suggest recording something when a conversation starts
exploring directions, decisions or questions — and wants to **measure first**, so the nudge is
switched on only when the numbers say it would help and not just nag.

## Goals

1. A new `UserPromptSubmit` hook that recognises exploring-or-deciding language in a user message.
2. A **measure** mode (the default, silent): log each hit, and later work out from git whether a
   record-carrying commit followed in the same session.
3. A **nudge** mode: add one short line to Claude's context so Claude offers, in one line, to record
   what is settled or still open. Claude offers; the owner decides. Nothing is ever committed
   automatically.
4. `/ledger-tidy` reports the measurement in plain words, with samples of what fired, and proposes
   switching to nudge (or leaving it) from the numbers — the same calibrate-at-tidy loop the recall
   threshold uses.
5. A **session audit** (approach B, added by the owner 2026-11-18): after a session has ended, read
   its transcript, both sides, and find the decision moments the message hook cannot see — above all
   a proposal from Claude accepted with a bare "ok" or "a" — and whether a record followed. In
   `nudge` mode the next session's digest says so, so a decision that slipped past is offered for
   recording at the next start.

## Non-goals

- No model call anywhere; both detectors are keyword scorers, no network.
- No change to the commit gate, the sync, or any entry's status. F-5eb5445 stays open until the
  measurement says whether the nudge worked.

## Anti-goals (a failure even if it technically works)

- **Nagging.** A nudge that fires on every other message, or after a record was just made, trains
  everyone to ignore it. Hence the rate limits below.
- **Writing into the repo.** F-266bd4e: a hook that rewrote a tracked file on every session start made
  a commit per session. Everything this hook records goes in the git dir, never in a tracked file.
- **Leaking prompt text** into a place it was not before. The log holds cue words and a pointer to the
  transcript the session already keeps; not the prompt.

## Constraints (all already settled; follow them)

- Hooks run through `bash`, files are written with LF, git output is read as UTF-8 (D-8db1c00, D-4a63728).
- Reading never writes the working tree (decision in 9d9fbe4); headless runs get no hook output.
- The trailer reader is the single one shared by the gate and the sync (D-38e1459). "Did a record
  follow" must use it, not a second regex.
- Per-clone state lives under the git common dir, shared by worktrees, never committed (the recall hook's `recall_dir`).

## Approaches considered

| | What | Trade-off | Outcome |
|---|---|---|---|
| **A** | Detect on the user's message; measure first, then nudge | Cheap and in-session; sees only the user's words, one message at a time, so a decision Claude proposes and the user accepts with "ok" is invisible | **Chosen** (owner, 2026-11-18) |
| **B** | Audit the whole transcript after the session, passive | Most accurate, sees both sides; but after the fact, so it cannot suggest anything during the conversation — the next digest can | **Chosen as well** (owner, 2026-11-18): it covers A's blind spot. Built as a lazy audit, not a `SessionEnd` hook (see Design) |
| C | A model judges each turn | Best at context; a model call per prompt, latency, and it hands the judgment to the layer that is supposed to be missing these | Rejected |

## Design

**Where it sits.** A second `UserPromptSubmit` hook, `ledger-capture.sh`, a thin wrapper like
`ledger-recall.sh` that calls `_ledger_parse.py capture-hook`. It is separate from recall so each has
its own switch and a failure in one cannot silence the other (one extra ~50 ms process; accepted).
Registered by `install.sh` beside the recall hook; stamped template **v12**.

**Configuration** (`.claude/ledger.conf`):

| Key | Default | Meaning |
|---|---|---|
| `CAPTURE` | `measure` | `measure` (log only), `nudge` (log and add the line), `off` |
| `CAPTURE_MIN` | `2` | cue score a message needs to count as a hit |
| `CAPTURE_GAP` | `10` | at most one nudge per this many prompts in a session |

**Detecting.** Ignore: slash commands, messages beginning `<` (pasted content, system notes),
fewer than 4 words, headless runs. Score the rest against a small lexicon in three families —
*direction* ("should we", "what if", "instead of", "alternatively", "which approach", "trade-off"),
*decision* ("let's go with", "we decided", "scrap that", "lock this in", "that's dead", "go with"),
*open question* ("not sure", "open question", "do we need", "how should we"). Start from the trigger
phrases already in the skill description, (a) to (g). Score = distinct cues matched; a decision-family
cue counts double. A hit is score ≥ `CAPTURE_MIN`. The lexicon is data in `_ledger_parse.py`, easy to
extend at tidy from what the samples show.

**Logging** (both modes), `<git-common-dir>/ledger-capture/log.tsv`, tab-separated, same rotation as
the recall log: `epoch, session, transcript path, kind, score, cues`. `kind` is `prompt` for every
counted message (the denominator; the cue score and word count ride along so short acceptances can be
counted), `hit` for a hit, `nudge` for a line actually emitted, `audit` for a session read back by the
audit (below), `told` for a digest line shown about one.

**Nudging** (only in `nudge` mode). Emit one line of `additionalContext`: the conversation looks like
it is weighing directions or decisions; when something is settled — or open and worth keeping —
offer in one line to record it (`Decision:` / `Opens:` via an empty commit, or `/ledger-note`); do
not interrupt to ask. Suppressed when: a nudge already went out within `CAPTURE_GAP` prompts in this
session; or a record-carrying commit landed in this repo during the session.

**The session audit (B).** No new hook. `capture_audit(root)` finds sessions that have prompt rows in
the log, have **ended** (last logged prompt older than the 15-minute grace) and have no `audit` row
yet, reads each transcript with the existing `_transcript_turns`, and appends one `audit` row:
`epoch, session, transcript path, audit, <decision-like human turns>, <accepted proposals>`. It is
called two places: the digest (capped at the three newest unaudited sessions and a transcript size
limit, so the 20 s hook budget is safe) and `tidy-report` (all of them), so the measurement never
depends on a hook having fired at exit or on a clean exit at all.

What it looks for, in turns it already separates into `human` and `agent`:

- **human decision-like turns** — the same lexicon as A, scored on the whole transcript (this also
  catches what A scored below `CAPTURE_MIN`, and is the check on A's recall);
- **accepted proposals** — an agent turn that offers a choice or asks for approval ("Which way",
  "Approve", "my recommendation", "Want me to", "Say so and I'll") followed directly by a short
  human reply (3 words or fewer) that agrees ("a", "yes", "ok", "approve", "go ahead", "do it").
  This is the case A cannot see, and the reason B exists.

An audited session is **covered** by the same test as for A's hits (below), over the whole
session window: first to last turn timestamp.

**What the next digest says (nudge mode only; silent in `measure`).** If the most recent audited
session has decision-like turns or accepted proposals and no record commit, the digest's
housekeeping block gains one line: *"Last session: 3 decision-like exchanges, no record commit —
ask whether to record them."* Shown once, then marked in the log (`told` row) so it does not repeat.
It adds to the digest's existing line budget; it does not extend the digest.

**Measuring.** `capture-stats` reads the log and git. A hit, or an audited session, is **covered**
when a commit carrying a record trailer (read with the shared trailer reader) lands between the hit
(or session start) and the end of that session; session end = the last logged prompt plus a
15-minute grace. Reported at tidy, since the last `CAPTURE` change:

> Capture (measuring): 212 messages, 31 hit (15%). 14 sessions audited; 9 had decision-like
> exchanges, 5 of those had a record commit afterwards, 4 did not. 11 of the 47 decision-like
> exchanges were bare acceptances ("ok", "a") — 23% the message hook could not see. Samples: …

with up to five hit messages and up to three accepted proposals quoted (read back from the
transcript path, locally) so the owner can say whether they were decision moments. Proposal rules,
mirroring the recall calibration, over sessions with a hit or decision-like exchanges: fewer than 30
hits **and** fewer than 10 such sessions → keep measuring, say how many more; otherwise propose
`CAPTURE=nudge` when at least 30% of those sessions had no record, and propose leaving it in
`measure` (or raising `CAPTURE_MIN`) when most were already covered or the samples were not decision
moments. A note-or-thought-only session reads as uncovered (call 6 below); the report says so in words.

**Resolving the finding.** Not at build time. After the nudge has run for a tidy period, compare
the uncovered share against the measure-only baseline; if it fell, close F-5eb5445 with that
evidence, otherwise record what was learned.

## Parts touched

`templates/hooks/ledger-capture.sh` (new) · `_ledger_parse.py` (settings, cue scorer, `capture-hook`,
`capture_audit`, `capture-stats`, a section in `tidy-report`, the digest line) · `templates/hooks/digest.sh`
(calls the audit and prints the line) · `install.sh` (copy, exec-bit list, UserPromptSubmit
registration, v12 stamp) · `templates/ledger.conf` · `commands/ledger-tidy.md` · `CHANGELOG.md` (v12) ·
`tests/run_tests.sh` (a new section after 13i) · this repo's own install, upgraded to v12 in
`measure` mode.

## Testing

No model needed: synthetic prompts through the hook on stdin; synthetic commits for "covered"/
"uncovered"; assertions that measure mode prints nothing; nudge mode prints one line and then not
again within the gap, nor after a record commit; slash commands, pasted content and headless runs
are silent; nothing is written outside the git dir; the report names the samples and the proposal
rules fire at the right counts. For B: a synthetic transcript (jsonl in Claude Code's format, as
`_transcript_turns` reads it) with a proposal and a bare "a" is audited as an accepted proposal; a
session with a record commit in its window is covered, without one is not; an unended session is not
audited; a session whose transcript is missing or unreadable is skipped without error; the digest
line appears in `nudge` mode only, once, and the digest stays inside its time and line budget with a
large transcript. Written to avoid the pipefail race fixed in d514003 (no
`grep … | grep -q` where the first grep can emit more than one buffer).

## Calls made without the owner (change any)

1. Separate hook rather than folding into recall.
2. Default mode `measure` everywhere, including repos upgraded to v12.
3. Log cue words plus the transcript pointer, not the prompt text.
4. 15-minute grace after the session's last prompt; 30-hit minimum and 30% uncovered rule; `CAPTURE_MIN=2`, `CAPTURE_GAP=10`.
5. A decision cue counts double.
6. "A record followed" means a commit with a record trailer. `/ledger-note` decisions, findings,
   opens, actions and retirements are empty commits, so they count. A `/ledger-note` **note** or
   **thought** is written straight into `LEDGER.md` with a bare date and no commit, so this
   measurement cannot see it: a session that was only noted will read as "uncovered". Accepted for
   v12, and stated in the report's wording; counting notes would need a dated-time signal they do not carry.

7. B is a lazy audit run by the digest and by tidy, not a `SessionEnd` hook: a `SessionEnd` hook
   cannot show anything to anyone, does not run when a terminal is killed, and would be one more hook
   to install and keep in step. The cost: a session is audited only at the *next* start or tidy, which
   is also when its result is wanted.
8. The audit's "accepted proposal" test is a phrase list on the agent turn plus a short human
   reply — deliberately crude; the samples at tidy are how its precision is judged.
9. B depends on Claude Code's transcript format, as recall's calibration already does; an
   unreadable or changed transcript makes a session unaudited, never an error.

## Left to the builder

The exact lexicon and proposal-phrase wording; column order inside the log; the transcript size
limit for the digest-time audit.
