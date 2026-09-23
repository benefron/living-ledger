#!/usr/bin/env python3
"""living-ledger — shared ledger parser, id helpers and trailer reader.

Copied verbatim into each repo as .claude/hooks/_ledger_parse.py. Entrypoints:

    _ledger_parse.py digest <LEDGER> <cutoff-date> <max_open> <max_recent> [<recent-paths-file>]
        -> the bounded session-start digest (markdown on stdout, empty if no entries).
           Overdue items first, then open items in the area being worked on.

    _ledger_parse.py block <LEDGER> <repo_id> <repo_path> <head> <state> <since> [<version>] [<max_open>]
        -> this repo's block for the cross-repo dashboard

    _ledger_parse.py stale-rules <LEDGER> <rules_dir>
        -> one line per .claude/rules/*.md that cites a closed finding or a superseded entry

    _ledger_parse.py lint <LEDGER>
        -> one line per defect the parser would otherwise skip silently

    _ledger_parse.py id <P> <text>
        -> the content-hash id for a new entry (e.g. F-3fa9c1e)

    _ledger_parse.py tidy-status <LEDGER> <repo_root> [<max_open>]
        -> one line saying why a tidy is due (volume of work + time since the last `Tidy:`
           commit), or nothing

    _ledger_parse.py tidy-report <LEDGER> <repo_root> [<max_open>]
        -> the candidates a /ledger-tidy pass reviews (markdown)

    _ledger_parse.py check-msg <commit-msg-file> <repo_root>
        -> the commit gate (called by .githooks/commit-msg): exit 1 with the reason on stderr
           if the message does not relate to the ledger. It reads trailers with the SAME
           function the sync uses, so what the gate accepts is exactly what gets recorded.

Entry ids are content hashes (`F-3fa9c1e`), never a counter: the same text gets the same id on
every clone and branch, so two machines or two branches can never hand out one id twice, and a
rebase or squash-merge leaves the id intact. Legacy sequential ids (`F-014`) are still parsed
everywhere and never renumbered.

ledger-template-version: 4
"""
import datetime
import hashlib
import io
import os
import re
import sys

# An entry id: a 7-hex content hash, or a legacy 3-6 digit sequence number.
ID_PAT = r'[A-Z]-(?:[0-9a-f]{7}|\d{3,6})'
ID_RE = re.compile(r'\b(' + ID_PAT + r')\b')
# The header is parsed leniently (any non-space id) so an odd hand-written entry is still an
# entry; `lint` is what reports it.
HDR = re.compile(r'^## (\S+) · (\S+) · (\S+) · (\S+) · (\d{4}-\d{2}-\d{2})(.*)$')
ENTRIES_MARKER = '<!-- ENTRIES_START -->'
STATUSES = ('OPEN', 'CLOSED', 'SUPERSEDED', 'STANDING')
TYPES = ('decision', 'finding', 'action', 'retired', 'note', 'thought')


# --- ids -----------------------------------------------------------------------

def norm_text(text):
    """Whitespace-collapsed, case-preserved text used for hashing and dedup."""
    return ' '.join(text.split())


def hash_id(prefix, text):
    """Content-hash id: <prefix>-<7 hex of sha1('<prefix>:' + normalized text)>."""
    h = hashlib.sha1(f'{prefix}:{norm_text(text)}'.encode('utf-8')).hexdigest()
    return f'{prefix}-{h[:7]}'


def is_legacy(eid):
    return re.fullmatch(r'[A-Z]-\d{3,6}', eid) is not None


# --- trailers ------------------------------------------------------------------

# Trailers that create an entry: key -> (id prefix, type, initial status)
KINDS = {
    'Decision': ('D', 'decision', 'CLOSED'),     # a settled choice, in force until superseded
    'Finding':  ('F', 'finding',  'STANDING'),   # a settled fact / result — nothing left to do
    'Opens':    ('F', 'finding',  'OPEN'),       # an open problem or question — something to resolve
    'Fixed':    ('F', 'finding',  'CLOSED'),     # a problem found AND resolved in this commit
    'Action':   ('A', 'action',   'OPEN'),       # a to-do; pair with `Due:` / `Owner:`
    'Retires':  ('R', 'retired',  'STANDING'),   # an approach that is now dead — never re-propose
}
RELATE_KEYS = ('Closes', 'Supersedes', 'Refs')   # act on existing entries by id
# Modifiers shape the entry trailer directly above them (or, placed before the first entry
# trailer, every entry of the commit). They never satisfy the commit gate on their own.
MODIFIER_KEYS = ('Due', 'Owner', 'Area', 'Pin', 'Date')
LORE_KEYS = ('Rejected', 'Constraint', 'Directive', 'Confidence', 'Scope-risk',
             'Reversibility', 'Tested', 'Not-tested', 'Related')
# `Tidy: <summary>` marks a /ledger-tidy pass: it creates nothing, and the next "tidy due"
# check counts work from it.
LEDGER_KEYS = tuple(KINDS) + RELATE_KEYS + ('Ledger', 'Tidy')
# Keys whose value may be wrapped onto following unindented lines.
WRAPPABLE = tuple(KINDS) + RELATE_KEYS + MODIFIER_KEYS + LORE_KEYS + ('Ledger', 'Tidy')


def supersede_ids(val):
    """`Supersedes: D-a, D-b by D-c` -> (['D-a', 'D-b'], ['D-c']). No `by`: (ids, [])."""
    left, sep, right = val.partition(' by ')
    return ID_RE.findall(left), (ID_RE.findall(right) if sep else [])

TOKEN_LINE = re.compile(r'^([A-Za-z][\w-]*):[ \t]+\S')


def _trailer_para(lines):
    """-> the paragraph's logical trailer lines, or None if it is not a trailer paragraph.

    A trailer paragraph starts with a `Token: value` line. Every other line is another
    `Token: value`, or a CONTINUATION of the one before it: indented (git's own rule), or, after
    a ledger/Lore key, simply wrapped — agents wrap long trailers at 72 columns, and a wrapped
    trailer must not take the whole block down with it.
    """
    if not lines or not TOKEN_LINE.match(lines[0]):
        return None
    out, key = [], None
    for raw in lines:
        m = TOKEN_LINE.match(raw)
        if m:
            key = m.group(1)
            out.append(raw.strip())
        elif raw[:1] in (' ', '\t') or key in WRAPPABLE:
            out[-1] = out[-1] + ' ' + raw.strip()
        else:
            return None
    return out


def trailer_lines(body):
    """The trailing trailer block of a commit message, as logical (unwrapped) lines.

    Walk paragraphs from the end, keeping each while it is a trailer paragraph. Prose that
    says "Decision:" mid-paragraph is never a trailer; neither is anything above the block.
    """
    paras = re.split(r'\n[ \t]*\n', body.strip())
    out = []
    for para in reversed(paras):
        got = _trailer_para([l.rstrip() for l in para.splitlines() if l.strip()])
        if got is None:
            break
        out = got + out
    return out


def stray_ledger_lines(body):
    """Ledger-keyed lines OUTSIDE the trailing block: they would be silently ignored."""
    paras = re.split(r'\n[ \t]*\n', body.strip())
    n = len(paras)
    kept = 0
    for para in reversed(paras):
        if _trailer_para([l.rstrip() for l in para.splitlines() if l.strip()]) is None:
            break
        kept += 1
    out = []
    for para in paras[1:n - kept]:          # never the subject paragraph
        for l in para.splitlines():
            m = TOKEN_LINE.match(l.strip())
            if m and m.group(1) in LEDGER_KEYS:
                out.append(l.strip())
    return out


# --- ledger file ---------------------------------------------------------------

def split_ledger(text):
    """-> (preamble up to and including the marker, entries text after it)."""
    if ENTRIES_MARKER in text:
        head, tail = text.split(ENTRIES_MARKER, 1)
        return head + ENTRIES_MARKER, tail
    return text, ''


def parse_blocks(entries_text):
    """Parse the entries section into dicts, in file order (newest first).

    Each dict: id, status, type, ws, date, suffix, lines (body lines, stripped), raw (the exact
    block, header included, no trailing blank lines). Text before the first header is returned
    as a pseudo-entry with id None so a round-trip never loses it.
    """
    entries, cur, raw, lead = [], None, [], []
    for line in entries_text.splitlines():
        m = HDR.match(line)
        if m:
            if cur is not None:
                cur['raw'] = '\n'.join(raw).rstrip()
            cur = dict(id=m.group(1), status=m.group(2), type=m.group(3), ws=m.group(4),
                       date=m.group(5), suffix=m.group(6), lines=[], raw='')
            raw = [line]
            entries.append(cur)
        elif cur is not None:
            raw.append(line)
            if line.strip() and not line.startswith('<!--'):
                cur['lines'].append(line.strip())
        else:
            lead.append(line)
    if cur is not None:
        cur['raw'] = '\n'.join(raw).rstrip()
    lead_text = '\n'.join(lead).strip()
    if lead_text:
        entries.insert(0, dict(id=None, status='', type='', ws='', date='', suffix='',
                               lines=[], raw=lead_text))
    return entries


def parse_entries(path):
    try:
        text = io.open(path, encoding='utf-8').read()
    except OSError:
        return []
    return [e for e in parse_blocks(split_ledger(text)[1]) if e['id']]


def insert_by_date(text, block):
    """Insert an entry block above the first existing entry dated on or before it, so the
    file stays newest-first even when older entries arrive late (a merge, a recovery). The
    order of existing entries is never rewritten. Blocks inserted oldest-first land in order."""
    m = HDR.match(block.split('\n', 1)[0])
    date = m.group(5) if m else '9999-99-99'
    head, sep, tail = text.partition(ENTRIES_MARKER)
    if not sep:
        return text
    pos = None
    for hm in re.finditer(r'^## .*$', tail, re.M):
        h = HDR.match(hm.group(0))
        if h and h.group(5) <= date:
            pos = hm.start()
            break
    block = block.rstrip('\n') + '\n'
    if pos is None:
        tail = tail.rstrip('\n') + '\n\n' + block
    else:
        tail = tail[:pos] + block + '\n' + tail[pos:]
    if not tail.startswith('\n\n'):
        tail = '\n\n' + tail.lstrip('\n')
    return head + sep + tail


def entry_text(e):
    """The entry's one-line statement: its first body line that is not a pointer/annotation."""
    return next((l for l in e['lines'] if l[:1] not in ('→', '·', '↔', '✓', '⤳')), '')


def entry_commit(e):
    for l in e['lines']:
        m = re.match(r'^→ commit ([0-9a-f]{4,})', l)
        if m:
            return m.group(1)
    return ''


def entry_meta(e, key):
    """Value of a `· Key: value` body line ('' if absent)."""
    pre = f'· {key}: '
    return next((l[len(pre):].strip() for l in e['lines'] if l.startswith(pre)), '')


def entry_due(e):
    v = entry_meta(e, 'Due')
    return v if re.fullmatch(r'\d{4}-\d{2}-\d{2}', v) else ''


def entry_pinned(e):
    return any(l == '· Pinned' for l in e['lines'])


# --- rendering helpers ----------------------------------------------------------

def _one(e, width=200, dated=False):
    ws = '' if e['ws'] == '-' else f" [{e['ws']}]"
    tags = []
    if entry_due(e):
        tags.append(f"due {entry_due(e)}")
    if entry_meta(e, 'Owner'):
        tags.append(f"owner {entry_meta(e, 'Owner')}")
    if dated:
        tags.append(e['date'])
    tag = f" ({', '.join(tags)})" if tags else ''
    return f"- {e['id']}{ws}{tag} {entry_text(e)}"[:width]


def _short(e, width=70):
    return f"{e['id']} {entry_text(e)}"[:width].rstrip()


def _tilde(p):
    home = os.path.expanduser('~')
    return '~' + p[len(home):] if home and p.startswith(home + os.sep) else p


def _recent_areas(paths_file):
    """Every leading path segment (a, a/b, a/b/c) of recently touched files."""
    areas = set()
    if not paths_file:
        return areas
    try:
        for line in io.open(paths_file, encoding='utf-8'):
            parts = [p for p in line.strip().split('/')[:-1] if p]
            for i in range(1, len(parts) + 1):
                areas.add('/'.join(parts[:i]))
                areas.add(parts[i - 1])
    except OSError:
        pass
    return areas


# --- commands --------------------------------------------------------------------

def _by_area(items, areas):
    """Stable partition: entries in a recently touched area first, file order within."""
    return [e for e in items if e['ws'] in areas] + [e for e in items if e['ws'] not in areas]


def cmd_digest(argv):
    # argv[1] (a cutoff date) is accepted for compatibility and no longer used: "recent" is
    # the newest entries, so the section survives a two-week break instead of going empty.
    path, max_open, max_recent = argv[0], int(argv[2]), int(argv[3])
    areas = _recent_areas(argv[4] if len(argv) > 4 else '')
    today = datetime.date.today().isoformat()
    entries = parse_entries(path)
    if not entries:
        return ''
    disp = _tilde(os.environ.get('LL_DISPLAY_PATH') or path)
    live = [e for e in entries if not is_dead(e)]
    openi = [e for e in entries if e['status'] == 'OPEN']
    overdue = sorted((e for e in openi if entry_due(e) and entry_due(e) <= today), key=entry_due)
    openi = overdue + _by_area([e for e in openi if e not in overdue], areas)
    pinned = [e for e in live if entry_pinned(e)]
    retire = _by_area([e for e in live if e['type'] == 'retired' and not entry_pinned(e)], areas)
    recent = [e for e in live if not entry_pinned(e) and (
        e['type'] == 'decision' or (e['type'] == 'finding' and e['status'] == 'STANDING'))]
    recent = _by_area(recent[:max_recent * 2], areas)[:max_recent]

    out = ["# Project ledger digest (auto-injected; full file: %s)" % disp, ""]
    out.append(f"{len(entries)} entries · {len(openi)} open"
               + (f" ({len(overdue)} overdue)" if overdue else "")
               + f" · {len(pinned)} pinned · {len(retire)} retired framings")
    out.append("")
    if openi:
        out.append(f"## Open ({len(openi)}) — problems, questions, actions; do not re-discover these")
        out += [_one(e) for e in openi[:max_open]]
        if len(openi) > max_open:
            out.append(f"- …{len(openi) - max_open} more: grep '· OPEN ·' {disp} "
                       f"— over the digest cap; triage (close, supersede, or demote)")
        out.append("")
    if pinned:
        out.append(f"## Pinned — in force; check before contradicting ({len(pinned)})")
        out += [_one(e, dated=True) for e in pinned[:12]]
        if len(pinned) > 12:
            out.append(f"- …{len(pinned) - 12} more: grep -B2 '^· Pinned' {disp}")
        out.append("")
    if recent:
        out.append("## Recently decided / established")
        out += [_one(e) for e in recent]
        out.append("")
    if retire:
        out.append(f"## Retired — settled; do NOT re-propose ({len(retire)})")
        out += [_one(e, width=160) for e in retire[:16]]
        if len(retire) > 16:
            out.append(f"- …{len(retire) - 16} more: grep '· retired ·' {disp}")
        out.append("")
    out.append("Every commit carries a ledger trailer — Decision: · Finding: (a fact) · Opens: (a "
               "problem) · Fixed: · Action: · Retires: · Closes:/Supersedes:/Refs: <id> — or "
               "`Ledger: none — <reason>`. A decision with no file change is an empty commit "
               "(`git commit --allow-empty --only`).")
    out.append("If something above looks wrong or stale, say so — do not silently work around it.")
    return "\n".join(out)


def is_dead(e):
    """No longer true / no longer in force. A decision is born CLOSED (a closed question) and
    stays in force, so only SUPERSEDED kills it; a finding or action dies when it is CLOSED."""
    if e['status'] == 'SUPERSEDED':
        return True
    return e['status'] == 'CLOSED' and e['type'] in ('finding', 'action')


def stale_rules(ledger_path, rules_dir):
    """Rules that outlived the entry they were written for.

    A path-scoped rule exists to stop one open finding being re-derived, or to hold a decision
    in force. Once the finding is closed or the decision superseded, the rule is telling future
    sessions something no longer true.
    """
    status = {e['id']: (e['status'] if is_dead(e) else '') for e in parse_entries(ledger_path)}
    out = []
    try:
        names = sorted(os.listdir(rules_dir))
    except OSError:
        return out
    for name in names:
        if not name.endswith('.md') or name == 'README.md':
            continue
        try:
            text = io.open(os.path.join(rules_dir, name), encoding='utf-8').read()
        except OSError:
            continue
        seen = []
        for eid in ID_RE.findall(text):
            st = status.get(eid)
            if st and eid not in seen:
                seen.append(eid)
                out.append('stale rule: %s cites %s (%s)' % (name, eid, st))
    return out


def cmd_stale_rules(argv):
    return "\n".join(stale_rules(argv[0], argv[1]))


def lint(path):
    """Defects that would otherwise be skipped silently by every reader of the ledger."""
    try:
        text = io.open(path, encoding='utf-8').read()
    except OSError:
        return []
    out = []
    if ENTRIES_MARKER not in text:
        return [f"no {ENTRIES_MARKER} marker — the sync has nowhere to insert entries"]
    pre, ent = split_ledger(text)
    base = pre.count('\n') + 1
    seen = {}
    for i, line in enumerate(ent.splitlines()):
        if not line.startswith('## '):
            continue
        n = base + i
        m = HDR.match(line)
        if not m:
            out.append(f"line {n}: header not in `## ID · STATUS · type · area · YYYY-MM-DD` form "
                       f"— invisible to the digest: {line[:80]}")
            continue
        eid, st, typ = m.group(1), m.group(2), m.group(3)
        if not re.fullmatch(ID_PAT, eid):
            out.append(f"line {n}: id {eid} is neither a content hash (X-1a2b3c4) nor legacy (X-014)")
        if st not in STATUSES:
            out.append(f"line {n}: {eid} has unknown status {st}")
        if typ not in TYPES:
            out.append(f"line {n}: {eid} has unknown type {typ}")
        if eid in seen:
            out.append(f"line {n}: duplicate id {eid} (first at line {seen[eid]})")
        else:
            seen[eid] = n
    return out


def cmd_lint(argv):
    return "\n".join(lint(argv[0]))


def cmd_block(argv):
    path, repo_id, repo_path, head, state, since = argv[:6]
    version = argv[6] if len(argv) > 6 else ''
    max_open = int(argv[7]) if len(argv) > 7 else 22
    stale = stale_rules(path, os.path.join(repo_path, '.claude', 'rules'))
    tidy = tidy_status(path, repo_path, max_open) if os.path.isdir(repo_path) else ''
    repo_path = _tilde(repo_path)
    today = datetime.date.today().isoformat()
    entries = parse_entries(path)  # file order == newest first
    openi = [e for e in entries if e['status'] == 'OPEN']
    overdue = [e for e in openi if entry_due(e) and entry_due(e) <= today]
    recent = [e for e in entries if e['type'] == 'decision' and e['status'] != 'SUPERSEDED'][:3]

    flags = []
    if state and state != 'clean':
        flags.append(state)
    try:
        n = int(since)
    except (TypeError, ValueError):
        n = 0
    if n > 0:
        what = "since last entry" if entries else "unrecorded"
        flags.append(f"{n} commit{'s' if n != 1 else ''} {what}")
    if overdue:
        flags.append(f"⏰ {len(overdue)} overdue")
    if len(openi) > max_open:
        flags.append(f"⚠ triage: {len(openi)} open > digest cap {max_open}")
    if tidy:
        flags.append("🧹 tidy due")

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    ver = f" · template v{version}" if version else ""
    out = [f"<!-- REPO:{repo_id} START -->",
           f"## {repo_id}  ·  {repo_path}",
           f"_rebuilt {stamp}_",
           f"HEAD {head or '?'} · "
           + (" · ".join(flags) if flags else "up to date")
           + f" · {len(openi)} open · {len(entries)} entries{ver}"]
    if overdue:
        out.append("**Overdue:** " + " · ".join(f"{_short(e, 60)} (due {entry_due(e)})"
                                                for e in overdue[:6]))
    if openi:
        shown = " · ".join(_short(e) for e in openi[:12])
        more = f" · …+{len(openi) - 12}" if len(openi) > 12 else ""
        out.append(f"**Open ({len(openi)}):** {shown}{more}")
    if recent:
        out.append("**Recent decisions:** " + " · ".join(_short(e) for e in recent))
    if stale:
        out.append("**Stale rules (%d):** " % len(stale)
                   + " · ".join(x[len('stale rule: '):] for x in stale[:6]))
    if not entries:
        out.append("_no entries yet — tracking forward from install_")
    out.append(f"<!-- REPO:{repo_id} END -->")
    return "\n".join(out)


def _conf(root, key):
    try:
        for line in io.open(os.path.join(root, '.claude', 'ledger.conf'), encoding='utf-8'):
            if line.startswith(key + '='):
                return line.split('=', 1)[1].strip()
    except OSError:
        pass
    return ''


def external_prefixes(root):
    """Id prefixes that belong to ANOTHER register (EXTERNAL_IDS=C in ledger.conf, e.g. a
    CONCERNS.md numbered C-001…): trailers may cite them, the ledger never owns them."""
    return {p for p in re.split(r'[\s,]+', _conf(root, 'EXTERNAL_IDS').strip('"\'')) if p}


def _ledger_path(root):
    rel = _conf(root, 'LEDGER_PATH')
    if rel:
        return os.path.join(root, rel)
    for c in ('docs_root/LEDGER.md', 'docs/LEDGER.md', 'LEDGER.md'):
        if os.path.exists(os.path.join(root, c)):
            return os.path.join(root, c)
    return ''


GATE_HELP = """  Add trailers in the LAST paragraph of the message (a blank line, then one per line;
  a long one may wrap onto the next line):

    Decision:   use a single-writer queue instead of a lock
    Finding:    the vendor API caps requests at 10/s          (a settled fact)
    Opens:      the cache is never invalidated after a deploy  (a problem to resolve)
    Fixed:      empty stanzas were silently dropped            (found and fixed here)
    Action:     ask the vendor for a higher rate limit         (+ Due: 2026-10-01)
    Retires:    "a nightly batch job is good enough"
    Closes:     F-3fa9c1e        Supersedes: D-8b1e0d2        Refs: F-3fa9c1e, D-014
    Ledger:     none — pure whitespace reformat, no behaviour change

  A decision with no file change:  git commit --allow-empty --only -m "decide: …" -m "Decision: …"
  Exempt: merges, reverts, fixup!/squash!, [bot] authors, LEDGER_SKIP=1, and EXEMPT_SUBJECTS /
  EXEMPT_AUTHORS (regexes) in .claude/ledger.conf.  Escape hatch:  git commit --no-verify
"""
ID_LED = re.compile(r'^[A-Z]{1,3}-[0-9A-Za-z]+\b')


def check_msg(msgfile, root):
    """-> list of problems (empty = the commit may proceed)."""
    if os.environ.get('LEDGER_SKIP', '').lower() in ('1', 'true', 'yes') \
            or os.environ.get('LEDGER_SYNC_IN_PROGRESS'):
        return []
    try:
        raw = io.open(msgfile, encoding='utf-8', errors='replace').read()
    except OSError:
        return []
    kept = []
    for line in raw.splitlines():
        if re.match(r'^[#;]?\s*-+ >8 -+', line):
            break                                   # `git commit -v` scissors
        if not line.startswith('#'):
            kept.append(line)
    body = '\n'.join(kept).strip()
    if not body:
        return []                                   # git aborts an empty message itself
    subject = body.splitlines()[0].strip()
    if re.match(r'^(Merge |merge: |Revert |Revert: |revert: |fixup! |squash! |amend! )', subject):
        return []
    import subprocess
    author = subprocess.run(['git', 'var', 'GIT_AUTHOR_IDENT'], capture_output=True, text=True,
                            cwd=root).stdout
    if '[bot]' in author:
        return []
    for key, target in (('EXEMPT_SUBJECTS', subject), ('EXEMPT_AUTHORS', author)):
        pat = _conf(root, key).strip('"\'')
        if pat:
            try:
                if re.search(pat, target):
                    return []
            except re.error:
                pass

    problems = []
    stray = stray_ledger_lines(body)
    if stray:
        problems.append("these ledger lines are NOT in the final trailer paragraph, so they would be "
                        "silently ignored:\n" + '\n'.join(f'      {l}' for l in stray)
                        + "\n    Move them into the last paragraph (no prose after them).")
    tl = trailer_lines(body)
    ledger = _ledger_path(root)
    try:
        known = {e['id'] for e in parse_entries(ledger)} if ledger else set()
    except Exception:
        known = set()
    declared = {m.group(1) for l in tl for m in [re.match(r'^Opens:\s+(F-\S+)\s+\S', l)] if m}
    ext = external_prefixes(root)
    related = entries = False
    for line in tl:
        key, _, val = line.partition(':')
        val = val.strip()
        if key in KINDS:
            lead = ID_LED.match(val)
            if key == 'Opens' and re.match(r'^F-(?:[0-9a-f]{7}|\d{3,6})\s+\S', val):
                entries = True
            elif lead and lead.group(0).split('-')[0] in ext and len(val[lead.end():].split()) >= 3:
                entries = True        # "Opens: C-032 -- <words>": cites the other register, has content
            elif lead:
                problems.append(f"`{key}: {val[:50]}` starts with an id. To relate this commit to an "
                                f"existing entry use `Refs: <id>` (or `Closes:`); `{key}:` records a "
                                f"new statement in words.")
            else:
                entries = True
        elif key == 'Tidy':
            related = True
        elif key in RELATE_KEYS:
            ids = ID_RE.findall(val)
            if not ids:
                problems.append(f"`{key}: {val[:40]}` names no entry id (ids look like F-3fa9c1e or F-014).")
            for i in ids:
                if i.split('-')[0] in ext:
                    continue              # an id of the other register: not the ledger's to check
                if ledger and os.path.exists(ledger) and i not in known and i not in declared:
                    problems.append(f"`{key}: {i}` — there is no entry {i} in "
                                    f"{os.path.relpath(ledger, root)}. (On another branch? Merge it "
                                    f"first, or use --no-verify.)")
            related = related or bool(ids)
        elif key == 'Ledger':
            m = re.match(r'^none\b[\s\W]*(.*)$', val, re.I)
            if m and len(m.group(1).split()) >= 3:
                related = True
            else:
                problems.append("`Ledger:` is only accepted as `Ledger: none — <reason, at least 3 "
                                "words>`.")
        elif key in ('Due', 'Date') and not re.fullmatch(r'\d{4}-\d{2}-\d{2}', val):
            problems.append(f"`{key}: {val}` must be a date, YYYY-MM-DD.")
    if not problems and not (entries or related):
        problems.append("this commit does not relate to the ledger.")
    return problems


def cmd_check_msg(argv):
    problems = check_msg(argv[0], argv[1] if len(argv) > 1 else os.getcwd())
    if problems:
        sys.stderr.write("\nliving-ledger: commit REJECTED — " + problems[0] + "\n")
        for p in problems[1:]:
            sys.stderr.write("  also: " + p + "\n")
        sys.stderr.write("\n" + GATE_HELP + "\n")
        sys.exit(1)
    return ''


# --- tidy: when it is due, and what it should look at -----------------------------

def _git(root, *args):
    import subprocess
    return subprocess.run(['git', '-C', root, *args], capture_output=True, text=True).stdout


def _counted_commits(root, rev_range):
    """Commits that are real work: no merges, no ledger sync commits, no [bot] authors, nothing
    matching EXEMPT_SUBJECTS / EXEMPT_AUTHORS."""
    exs = _conf(root, 'EXEMPT_SUBJECTS').strip('"\'')
    exa = _conf(root, 'EXEMPT_AUTHORS').strip('"\'')
    n = 0
    for line in _git(root, 'log', '--no-merges', '--format=%an <%ae>%x09%s', rev_range).splitlines():
        who, _, subj = line.partition('\t')
        if re.match(r'(chore|docs)(\(ledger\))?: (ledger|sync ledger)', subj) or '[bot]' in who:
            continue
        try:
            if (exs and re.search(exs, subj)) or (exa and re.search(exa, who)):
                continue
        except re.error:
            pass
        n += 1
    return n


def tidy_baseline(ledger, root):
    """-> (sha, date, label): the last `Tidy:` commit, else the commit that created the ledger."""
    last = _git(root, 'log', '-1', '--format=%H%x09%cs', '--grep=^Tidy:', 'HEAD').strip()
    if last:
        sha, date = last.split('\t')
        return sha, date, f'the last tidy ({date})'
    # the ledger may be read from a temp copy (the digest's view): git history needs the real path
    rel = _conf(root, 'LEDGER_PATH') or os.path.relpath(ledger, root)
    born = _git(root, 'log', '--diff-filter=A', '--format=%H%x09%cs', 'HEAD', '--', rel).strip()
    if born:
        sha, date = born.splitlines()[-1].split('\t')
        return sha, date, f'the ledger began ({date}; never tidied)'
    return '', '', ''


def tidy_status(ledger, root, max_open=22):
    """Why a tidy is due, or ''. Volume of work and time both count: a quiet month is not due,
    a one-day burst of fifty entries is; a busy fortnight is. Thresholds: TIDY_MIN_DAYS (7) and
    TIDY_VOLUME (25) in ledger.conf, where volume = new entries + 3 x merges + commits / 5."""
    entries = parse_entries(ledger)
    if not entries:
        return ''
    sha, base_date, label = tidy_baseline(ledger, root)
    if not sha:
        return ''
    tidied = label.startswith('the last tidy')
    new = [e for e in entries if (e['date'] > base_date if tidied else e['date'] >= base_date)
           or not tidied]
    commits = _counted_commits(root, f'{sha}..HEAD')
    merges = len(_git(root, 'rev-list', '--merges', f'{sha}..HEAD').split())
    days = (datetime.date.today() - datetime.date.fromisoformat(base_date)).days
    openi = sum(1 for e in entries if e['status'] == 'OPEN')
    try:
        min_days = int(_conf(root, 'TIDY_MIN_DAYS') or 7)
        vol_need = int(_conf(root, 'TIDY_VOLUME') or 25)
    except ValueError:
        min_days, vol_need = 7, 25
    volume = len(new) + 3 * merges + commits // 5
    due = (days >= min_days and volume >= vol_need) or volume >= 3 * vol_need or openi > max_open
    if not due:
        return ''
    why = (f"{len(new)} new entries, {merges} merge{'s' if merges != 1 else ''} and "
           f"{commits} commit{'s' if commits != 1 else ''} over {days} day{'s' if days != 1 else ''} "
           f"since {label}")
    if openi > max_open:
        why += f"; {openi} open items, over the digest cap of {max_open}"
    return why


def cmd_tidy_status(argv):
    return tidy_status(argv[0], argv[1], int(argv[2]) if len(argv) > 2 else 22)


STOP = set('the a an and or of to in on for with by is are be as at from that this it its not no '
           'into than then when only each every one two all any must should can will was were has '
           'have had but so if per via use used uses using new now also more less same'.split())


def _toks(text):
    return {w for w in re.findall(r'[a-z0-9_]{3,}', text.lower()) if w not in STOP}


def tidy_report(ledger, root, max_open=22):
    """The candidates a tidy pass reviews. Heuristics only — every item is a proposal for the
    user to accept, edit or decline, never an automatic change."""
    entries = parse_entries(ledger)
    today = datetime.date.today()
    out = []
    status = tidy_status(ledger, root, max_open)
    sha, base_date, label = tidy_baseline(ledger, root)
    live = [e for e in entries if not is_dead(e)]
    openi = [e for e in entries if e['status'] == 'OPEN']
    by_commit = {}
    for e in entries:
        by_commit.setdefault(entry_commit(e), []).append(e)

    def line(e, why, act, width=90):
        return f"- {e['id']} · {entry_text(e)[:width]} — {why} → {act}"

    def section(title, items, cap=25):
        if items:
            out.append(f"## {title} ({len(items)})")
            out.extend(items[:cap])
            if len(items) > cap:
                out.append(f"- …{len(items) - cap} more")
            out.append('')

    out.append(f"# Ledger tidy report — {_conf(root, 'LEDGER_PATH') or os.path.relpath(ledger, root)}")
    out.append('')
    out.append(f"{len(entries)} entries · {len(live)} live · {len(openi)} open · since {label or 'n/a'}"
               + (f" · due: {status}" if status else " · not due yet"))
    out.append('')

    # 1. open items that look settled
    settled = []
    fact = re.compile(r'\b(fixed|resolved|reproduc\w*|confirm\w*|refuted|verified|no change (is )?needed|'
                      r'now (passes|works)|measured|holds|is correct)\b', re.I)
    for e in openi:
        c = entry_commit(e)
        partners = [x['id'] for x in by_commit.get(c, []) if x is not e and x['type'] == 'decision'] if c else []
        subj = _git(root, 'show', '-s', '--format=%s', c).strip() if c else ''
        if fact.search(entry_text(e)):
            settled.append(line(e, 'reads like a settled result', 'STANDING (a fact) or CLOSED'))
        elif partners:
            settled.append(line(e, f'opened in the same commit as {", ".join(partners)}',
                                'CLOSED if that decision resolved it'))
        elif re.match(r'fix\b|fix[(:]', subj):
            settled.append(line(e, f'born in a fix commit ({c})', 'CLOSED if the fix covers it'))
    section('Open, but possibly settled', settled)

    # 2. overdue and aging open items
    aging = []
    for e in openi:
        due = entry_due(e)
        age = (today - datetime.date.fromisoformat(e['date'])).days
        if due and due <= today.isoformat():
            aging.append(line(e, f'overdue since {due}', 'close, re-date (new Due:) or drop'))
        elif age > 30 and not any(l[:1] in ('↔', '✓') for l in e['lines']):
            aging.append(line(e, f'open {age} days, never referenced since', 'still real? close or keep'))
    section('Overdue or aging', aging)

    # 3. near-duplicates and possible contradictions among live entries of one type
    dups = []
    for typ in ('decision', 'finding', 'action', 'retired'):
        group = [(e, _toks(entry_text(e))) for e in live if e['type'] == typ]
        for i in range(len(group)):
            a, ta = group[i]
            if len(ta) < 3:
                continue
            for b, tb in group[i + 1:]:
                if len(tb) < 3:
                    continue
                # Jaccard catches rewordings; the overlap coefficient catches a short restatement
                # of a longer entry, but only on entries long enough not to match by accident.
                # Measured on real ledgers: no false positives at these settings.
                shared = len(ta & tb)
                if shared / len(ta | tb) >= 0.3 or (min(len(ta), len(tb)) >= 5
                                                    and shared / min(len(ta), len(tb)) >= 0.6):
                    dups.append(f"- {a['id']} ≈ {b['id']} · {entry_text(a)[:60]} | {entry_text(b)[:60]}"
                                f" → same thing (Supersedes: <older> by <newer>), a refinement, or a"
                                f" contradiction to settle")
    section('Similar entries — duplicate, refinement or contradiction?', dups)

    # 4. entries with no content of their own
    junk = [line(e, 'no content of its own', 'Supersedes: <it> by <the real entry>, or reword by hand')
            for e in live if len(entry_text(e).split()) <= 2 or re.fullmatch(ID_PAT, entry_text(e).strip())]
    section('Empty or id-only entries', junk)

    # 5. pinned entries worth re-confirming
    pins = [line(e, f'pinned since {e["date"]}', 'still in force? keep, or unpin (delete the · Pinned line)')
            for e in live if entry_pinned(e)
            and (today - datetime.date.fromisoformat(e['date'])).days > 60]
    section('Pinned for over 60 days', pins)

    # 6. recent decisions whose reasoning was never written down
    dec_rel = _conf(root, 'DECISIONS_PATH')
    try:
        dec_text = io.open(os.path.join(root, dec_rel), encoding='utf-8').read() if dec_rel else ''
    except OSError:
        dec_text = ''
    thin = []
    for e in live:
        if e['type'] != 'decision' or not base_date or e['date'] < base_date or e['id'] in dec_text.split(
                '<!-- DECISIONS_LOG_START -->')[0]:
            continue
        c = entry_commit(e)
        if not c:
            continue                      # hand-written / backfilled: its evidence is elsewhere
        body = _git(root, 'show', '-s', '--format=%B', c)
        paras = [p for p in re.split(r'\n\s*\n', body.strip())[1:] if p.strip()]
        prose = [p for p in paras if _trailer_para([l for l in p.splitlines() if l.strip()]) is None]
        if not prose:
            thin.append(line(e, 'no reasoning in its commit body or DECISIONS.md', 'add a DECISIONS.md section, or accept as self-evident'))
    section('Decisions with no written reasoning', thin, cap=15)

    # 7. rules and headers
    rules = stale_rules(ledger, os.path.join(root, '.claude', 'rules'))
    section('Stale path-scoped rules', [f"- {r}" for r in rules])
    section('Lint', [f"- {x}" for x in lint(ledger)])

    # 8. other registers that can drift from this one
    led_rel = _conf(root, 'LEDGER_PATH') or os.path.relpath(ledger, root)
    others = [f for f in _git(root, 'ls-files').splitlines()
              if re.search(r'(?i)(retired|concern|decision|adr|handoff|status)[^/]*\.md$', f)
              and f not in (led_rel, dec_rel)]
    section('Other registers to keep consistent (or reduce to a pointer)', [f"- {f}" for f in others], cap=12)

    if len(out) <= 4:
        out.append("Nothing to tidy.")
    return "\n".join(out)


def cmd_tidy_report(argv):
    return tidy_report(argv[0], argv[1], int(argv[2]) if len(argv) > 2 else 22)


def cmd_id(argv):
    return hash_id(argv[0], ' '.join(argv[1:]))


def main():
    if len(sys.argv) < 2:
        sys.exit(2)
    mode, rest = sys.argv[1], sys.argv[2:]
    fn = {'digest': cmd_digest, 'block': cmd_block, 'stale-rules': cmd_stale_rules,
          'lint': cmd_lint, 'id': cmd_id, 'check-msg': cmd_check_msg,
          'tidy-status': cmd_tidy_status, 'tidy-report': cmd_tidy_report}.get(mode)
    if fn is None:
        sys.exit(2)
    s = fn(rest)
    if s:
        print(s)


if __name__ == '__main__':
    sys.dont_write_bytecode = True
    main()
