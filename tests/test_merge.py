#!/usr/bin/env python3
"""Unit tests for templates/hooks/ledger-merge.py (run: python3 tests/test_merge.py)."""
import io
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOKS = os.path.join(ROOT, 'templates', 'hooks')
sys.path.insert(0, HOOKS)
from _ledger_parse import hash_id, parse_blocks, split_ledger  # noqa: E402

PRE = "# Ledger\n\nprose\n\n<!-- ENTRIES_START -->\n"


def entry(eid, status, text, sha, date='2026-09-20'):
    return f"## {eid} · {status} · finding · - · {date}\n{text}\n→ commit {sha}\n"


def run_merge(base, ours, theirs, block=False):
    d = tempfile.mkdtemp()
    paths = []
    for name, content in (('base', base), ('ours', ours), ('theirs', theirs)):
        p = os.path.join(d, name)
        with io.open(p, 'w', encoding='utf-8') as f:
            f.write(content)
        paths.append(p)
    args = ['python3', os.path.join(HOOKS, 'ledger-merge.py')] + (['--block'] if block else []) + paths
    r = subprocess.run(args, capture_output=True, text=True)
    with io.open(paths[1], encoding='utf-8') as f:
        return r.returncode, f.read(), r.stderr


class MergeTests(unittest.TestCase):
    def test_disjoint_inserts_union(self):
        base = PRE + "\n" + entry('F-001', 'OPEN', 'old', 'aaaaaaa')
        ours = PRE + "\n" + entry('F-1111111', 'OPEN', 'ours new', 'bbbbbbb') + "\n" + entry('F-001', 'OPEN', 'old', 'aaaaaaa')
        theirs = PRE + "\n" + entry('F-2222222', 'OPEN', 'theirs new', 'ccccccc') + "\n" + entry('F-001', 'OPEN', 'old', 'aaaaaaa')
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        ids = [e['id'] for e in parse_blocks(split_ledger(out)[1])]
        self.assertEqual(sorted(ids), ['F-001', 'F-1111111', 'F-2222222'])
        self.assertNotIn('<<<<<<<', out)

    def test_closed_beats_open(self):
        base = PRE + "\n" + entry('F-001', 'OPEN', 'thing', 'aaaaaaa')
        ours = base
        theirs = PRE + "\n" + entry('F-001', 'CLOSED', 'thing', 'aaaaaaa')
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        self.assertIn('## F-001 · CLOSED', out)
        rc, out, _ = run_merge(base, theirs, ours)   # symmetric
        self.assertIn('## F-001 · CLOSED', out)

    def test_true_collision_rekeys_theirs(self):
        base = PRE
        ours = PRE + "\n" + entry('D-013', 'CLOSED', 'the web UI is the only GUI going forward.', '45085b5')
        theirs = PRE + "\n" + entry('D-013', 'CLOSED', 'the default retry budget is three attempts', '9f9f9f9')
        rc, out, err = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        es = {e['id']: e for e in parse_blocks(split_ledger(out)[1])}
        self.assertIn('D-013', es)
        self.assertIn('web UI', es['D-013']['raw'])
        new_id = hash_id('D', 'the default retry budget is three attempts')
        self.assertIn(new_id, es)
        self.assertIn('· was D-013 — renamed on merge', es[new_id]['raw'])
        self.assertIn('allocated twice', err)

    def test_legacy_and_hash_id_for_same_entry_collapse(self):
        base = PRE
        ours = PRE + "\n" + entry('F-7037aa8', 'OPEN', 'the timeout must exceed the poll interval', 'dea696a')
        theirs = PRE + "\n" + entry('F-008', 'CLOSED', 'the timeout must exceed the poll interval', 'dea696a')
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        ids = [e['id'] for e in parse_blocks(split_ledger(out)[1])]
        self.assertEqual(ids, ['F-008'])
        self.assertIn('## F-008 · CLOSED', out)

    def test_preamble_both_changed_conflicts(self):
        base = PRE
        ours = PRE.replace('prose', 'ours prose')
        theirs = PRE.replace('prose', 'theirs prose')
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 1)
        self.assertIn('<<<<<<< ours', out)

    def test_preamble_disjoint_edits_merge_cleanly(self):
        base = "# Ledger\n\nline one\n\nline two\n\nline three\n\n<!-- ENTRIES_START -->\n"
        ours = base.replace('line one', 'line ONE')
        theirs = base.replace('line three', 'line THREE')
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        self.assertIn('line ONE', out)
        self.assertIn('line THREE', out)

    def test_both_sides_backlink_the_same_entry(self):
        e = entry('D-1234567', 'CLOSED', 'use a queue', 'aaaaaaa')
        base = PRE + "\n" + e
        ours = PRE + "\n" + e.rstrip('\n') + "\n↔ bbbbbbb feat: ours\n"
        theirs = PRE + "\n" + e.rstrip('\n') + "\n↔ ccccccc feat: theirs\n"
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        self.assertIn('↔ bbbbbbb', out)
        self.assertIn('↔ ccccccc', out)
        self.assertEqual(out.count('## D-1234567'), 1)

    def test_theirs_new_entries_go_on_top(self):
        old = entry('F-001', 'OPEN', 'old', 'aaaaaaa')
        base = PRE + "\n" + old
        ours = base
        theirs = PRE + "\n" + entry('F-2222222', 'OPEN', 'new on theirs', 'ccccccc') + "\n" + old
        rc, out, _ = run_merge(base, ours, theirs)
        ids = [e['id'] for e in parse_blocks(split_ledger(out)[1]) if e['id']]
        self.assertEqual(ids, ['F-2222222', 'F-001'])

    def test_one_sided_edit_wins(self):
        base = PRE + "\n" + entry('N-003', 'STANDING', 'a note', '')
        ours = base
        theirs = base.replace('a note', 'a note, reworded')
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertIn('a note, reworded', out)
        self.assertEqual(out.count('## N-003'), 1)

    def test_decisions_log_rows_union(self):
        head = "# Decisions\n\nprose\n\n<!-- DECISIONS_LOG_START -->\n"
        tail = "<!-- DECISIONS_LOG_END -->\n"
        r1 = "| 2026-09-01 | D-001 | first | `a` |\n"
        base = head + r1 + tail
        ours = head + r1 + "| 2026-09-03 | D-3333333 | ours | `c` |\n" + tail
        theirs = head.replace('prose', 'prose, edited') + r1 + "| 2026-09-02 | D-2222222 | theirs | `b` |\n" + tail
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        self.assertIn('prose, edited', out)
        self.assertLess(out.index('D-001'), out.index('D-2222222'))
        self.assertLess(out.index('D-2222222'), out.index('D-3333333'))

    def test_decisions_log_dotted_rows_union(self):
        head = "# D\n\n<!-- DECISIONS_LOG_START -->\n"
        tail = "<!-- DECISIONS_LOG_END -->\n"
        r1 = "2026-09-01 · D-001 · first · aaa\n"
        base = head + r1 + tail
        ours = head + r1 + "2026-09-03 · D-3333333 · ours · ccc\n" + tail
        theirs = head + r1 + "2026-09-02 · D-2222222 · theirs · bbb\n" + tail
        rc, out, _ = run_merge(base, ours, theirs)
        self.assertEqual(rc, 0)
        self.assertEqual(out.count('D-001'), 1)
        self.assertLess(out.index('D-2222222'), out.index('D-3333333'))

    def test_block_newest_stamp_wins(self):
        ours = "## r\n_rebuilt 2026-09-20T10:00:00Z_\nHEAD a\n"
        theirs = "## r\n_rebuilt 2026-09-22T10:00:00Z_\nHEAD b\n"
        rc, out, _ = run_merge('', ours, theirs, block=True)
        self.assertEqual(rc, 0)
        self.assertIn('HEAD b', out)
        rc, out, _ = run_merge('', theirs, ours, block=True)
        self.assertIn('HEAD b', out)


if __name__ == '__main__':
    unittest.main()
