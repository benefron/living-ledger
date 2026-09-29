# The ledger at work: evidence from four repositories

*Measured on 2026-09-29 from each repository's default branch, plus the recall logs and session
transcripts on one of the two machines. Every number comes from git history. The scripts that
produced them read commits, trailers and the ledger file, and nothing else.*

The four repositories:
- a **research simulation** (encoder and decoder models, and a talk deck);
- a **neuron-simulator package** it depends on;
- a **hardware controller** for a multi-electrode chip, worked from a Windows lab PC;
- a **lab-experiment protocol** that runs on that chip, also worked from the Windows PC.

| | research simulation | simulator package | hardware controller | lab protocol |
|---|---|---|---|---|
| ledger installed | 27 Aug | 14 Sep | 14 Sep | 9 Sep |
| entries on 23 Sep → 29 Sep | 220 → 265 | 138 → 177 | 45 → 60 | 199 → 203 |
| open on 23 Sep → 29 Sep | 24 → 30 | 17 → **0** | 19 → **5** | 85 → **5** |
| items closed by a commit | 32 | 87 | 15 | 34 |
| …closed after lingering 7+ days | 18 | 3 | 11 | 24 |
| `Supersedes:` (a decision revised, with its trail) | 28 | 0 | 2 | 4 |
| `Refs:` (work tied to an earlier entry) | 54 | 69 | 2 | 2 |
| commits whose message cites an entry id | 45 | 130 | 14 | 29 |
| files in the tree that cite an entry id | 90 | 208 | 14 | 82 |
| first tidy | 23 Sep | 24 Sep | 25 Sep | 25 Sep |

Across the four repositories there are 705 entries and 168 items closed by a commit. 161
trailers revise or build on an earlier entry, and 394 files cite an entry id.

## Resolving lingering issues

Across the four, 56 items stayed open a week or more before a commit closed them. The median
item was closed 10–15 days after it was opened, except in the simulator package, where most
were closed the same day.

The first tidy of each ledger did most of the clearing, and each tidy commit says what it found:
- **Lab protocol:** 85 open → 11. 26 resolved items closed, 53 settled facts marked as such, and
  2 duplicates folded. Most of the 85 were results that the pre-v4 parser had recorded as open
  problems.
- **Hardware controller:** 19 open → 5. Two findings were answered the same day on the rig: that
  stimulation fires in stream-only mode, and that the vendored client has the streaming RPCs.
  Ten had been resolved in the very commits that recorded them.
- **Simulator package:** 17 open on 23 September, none now. Its tidy closed one item that was
  already fixed and marked eight settled results. It also gave six GUI and stimulus decisions with
  no written reasoning DECISIONS.md sections, drawn from their commits. Later commits closed the
  rest.
- **Research simulation:** 41 open → 24, reviewed item by item with the user. The pending calls
  listed in a status document were not in the ledger at all; they became owned, dated items.

The research simulation is the one whose open list grew since (24 → 30). It is in its busiest
phase: 147 commits since 23 September, 56 of them recording entries.

## Referencing decisions where the work happens

Commits say which decision they carry out, in words and in trailers:
- *"Enacts D-ce22df3, D-8dde454, D-673e0ed and D-4e669b4."* (simulator package, neuron defaults)
- *"Enacts D-4a8de09 and D-a8f847d."* (research simulation, gain matching)
- *"Review of PR #17: D-407c639 changed only GaborTexture's defaults…"* (a review finding traced
  to the decision it left half-done)

The ids also live in the code and tests, at the point where a future change would break them.
In the simulator package, 94 test files and 55 source files cite an entry, for example
`# F-040: --duration now reaches every stimulus`. The hardware controller's code cites the lab
protocol's findings by id (F-097, F-079), so one repository's ledger is read from another's code.

## Keeping the record true

When the ledger's answer changes, the code catches up. On the hardware controller, a docstring
"still called F-003 open"; after the rig run answered F-003, a commit corrected the docstring
and cited the run. Superseded decisions keep their trail: the research simulation has revised
28 entries by `Supersedes:`, and each old entry points at what replaced it.

## Recall (prompt-time search), early numbers

Recall started on 24 September. On this machine it has run on 16 prompts in two repositories.
It showed 14 entries, and Claude cited 3 of them in its answer. In the research simulation it
fired on 6 of 11 prompts, far more often than the 13% the replay predicted. That's too small a
sample to act on. It is exactly what the tidy-time calibration watches: it proposes a new
threshold once 30 recalls are logged. Most of the week's work ran in cloud sessions, whose
transcripts are not on this machine, so these numbers undercount.

## What running it on Windows found

The lab PC ran the v1 digest and sync through September and the v5 upgrade on 24 September. It
exposed three bugs:
1. **The executable bit.** Git on Windows ignores it, so the upgrade committed the hook scripts
   as non-executable, and on the Mac the commit gate for those repositories silently stopped
   running. Fixed in v6.
2. **Line endings.** The ledger was written with Windows line endings. Fixed in v6.
3. **Encoding.** One merge wrote 30 lines of mojibake, which the hardware controller's first tidy
   found and repaired. Fixed in v7.

All three were found by using the ledger itself: a tidy, and pulling the repositories on the
other machine.

## Limits of this evidence

Counts of closes and citations show that the ledger is being used, not that it caused better
work. Whether it stops sessions re-proposing retired approaches is the point of the tool, and
nothing here counts it. All four repositories have one developer.
