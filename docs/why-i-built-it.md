# My repo is my lab notebook. Now it remembers what we decided.

*Why I built living-ledger, and what a month of using it has been like.*

I've been working with LLMs since ChatGPT became publicly available, pushing them and refining
how I work with them. Early on I built custom GPTs for my scientific work, back when all you
could give one was a single saved set of instructions. Since then, many of the workarounds I
(and I'm sure many others) built for ourselves have become standard features of agentic tools:
plans, instruction files, memory.

I'm not a software engineer. For me, code has always been a means to an end: data analysis,
hardware control, data acquisition, experiment automation, pipelines. But some ideas from
software engineering map directly onto research, version control above all. So my work moved
easily from ChatGPT on the desktop to VS Code with GitHub Copilot, and from there to Claude
Code. My repositories became a kind of lab notebook. They hold the code, documents,
presentations and decisions. The hypothesis, the design and the pipeline keep evolving as code
runs, experiments come in and I look at the results.

## The housekeeping problem

Working like that, Claude's memory wasn't enough. It can't know which decisions are the right
ones or what's still open. Above all, it can't know what was settled in the middle of a
discussion.

My first step was markdown files: architectural decisions, blueprints, scientific hypotheses.
But those files go stale, and every time something drifts or changes they have to be updated. My
repos overgrew with docs, archived docs, a docs root and more directories, and keeping them in
order became a job of its own. It cost tokens and context, but mostly it cost my time. I spent
whole sessions reading files, reorganizing directories and archiving, instead of moving the
research forward. What I got was a project that was hard to follow, for the agent and for me.
And it was still on me to remember the latest decisions, point Claude to the files that held
them, and keep the README and CLAUDE.md current.

Hooks and reference files helped, but I wanted a principled way. In those clean-up sessions I
kept sending the agent to the recent commits, to work out which files were current. That has a
blind spot: the settled, working parts of a project are exactly the ones recent commits don't
touch. Still, commits felt like the right place to look for what had been decided, if only they
said so explicitly, instead of holding a diff and a bit of text.

## Decisions in the commits

I wasn't the only one with that idea. Ivan Stetsenko's **Lore** paper
([arXiv:2603.15566](https://arxiv.org/abs/2603.15566)) treats commits as the atomic unit of a
project's knowledge. The reasoning goes into the commit message as structured trailers, so it
can't drift from the code it belongs to.

I built on it in my most complicated repository. It's a full scientific project with a
simulation engine, spiking neural networks, data analysis and state-space models, all evolving
constantly. There I kept being offered ideas that had already been rejected, suppressed or ruled
irrelevant. This is how it works:

- **You work as usual.** When a decision is reached, a finding comes in, an approach turns out
  to be a dead end or a to-do comes up, Claude proposes a one-line record. You approve it, edit
  it, or say no. Claude puts it on the commit it's making. When there's no code to commit, as
  with a decision about scope, a deadline or what a paper should claim, it goes on an empty
  commit.
- **Every record gets an id:** a letter for its kind plus a short hash. `D-3fa9c1e` is a
  decision, `F-` a finding or open problem, `A-` an action, `R-` a retired approach. Commits,
  code comments and other records can point to it.
- **One file holds them all.** A git hook builds `LEDGER.md` from the commits. Nobody edits it by
  hand, and anyone can open it and read what's going on. Longer reasoning goes in
  `DECISIONS.md`.
- **It works in the background.** Every session starts with a short digest of what's open,
  decided and ruled out. Each message I type is also checked against the whole ledger, for
  entries the digest didn't show.
- **Every commit is checked.** A commit with no record is refused unless it says why it needs
  none. So is a decision that brings back a rejected approach without saying so.
- **Decisions change, and the trail stays.** A new decision supersedes the old one, which points
  to its replacement. An open item is closed by the commit that resolves it.
- **Clean-up is short.** When enough work has piled up, Claude suggests `/ledger-tidy`. It
  reviews what's open, folds duplicates and flags contradictions, and I approve each change.

## A month in

It soon spread to my other repositories, with some shared information across related projects.
`/ledger-status` shows what's open in all of them. It has been updated constantly since, every
version driven by a bug or a use case in those repositories, and it's now at version 10.

It doesn't stop every drift, and it still needs some watching. But the questions that used to
cost a clean-up session now take a quick search: what's still open, what's relevant here, does
this contradict an earlier decision. I don't have exact numbers for the time or tokens saved,
but [a report in the repository](https://github.com/benefron/living-ledger/blob/main/docs/evidence.md)
covers four of my repositories:
- **Entries:** 705 so far.
- **Closed items:** 168 open items were closed by commits, 56 of them after lingering a week or
  more.
- **Tidies:** one open list went from 85 items to 11 in a single tidy.
- **Revisions:** no decision was revised and then brought back.

Day to day, my discussions with the agent are better informed and more to the point. I do much
less housekeeping, and when I do, it's quick. I've used the ledger to find what was left open
and close much of it. And because the ledger is plain, readable markdown, I can follow my own
project again.

## Try it

This is the first tool I built for my own use that I'm sharing with the world. It's made for
Claude Code; the ledger itself is plain git, bash and Python.

```bash
git clone https://github.com/benefron/living-ledger ~/.claude/skills/living-ledger
~/.claude/skills/living-ledger/install.sh --global-only
```

Then run `/ledger-init` in a repository. I hope you find it useful, and I'd like to hear if you
do. Comments and suggestions are welcome: open an issue or send me a message.
