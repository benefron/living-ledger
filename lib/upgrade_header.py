#!/usr/bin/env python3
"""living-ledger — additive LEDGER.md header upgrade.

    upgrade_header.py <LEDGER.md> <decisions_rel> <lore.md> <three-levels.md>

Adds standard header paragraphs that an older ledger does not have yet. Everything from
`<!-- ENTRIES_START -->` onwards is copied through byte for byte — entries are never
touched — and a repo's own customisations of the header (its grep examples, its column
names, its extra sections) are never rewritten, only appended beside.

Prints a one-line summary of what it added, or nothing.

ledger-template-version: 6
"""
import io
import sys

MARK = '<!-- ENTRIES_START -->'


def main():
    ledger, dec_rel, lore_f, three_f = sys.argv[1:5]
    s = io.open(ledger, encoding='utf-8').read()
    head, sep, tail = s.partition(MARK)
    if not sep:                       # unrecognised shape — do nothing at all
        return
    orig, added = head, []

    lore = io.open(lore_f, encoding='utf-8').read().strip()
    three = (io.open(three_f, encoding='utf-8').read().strip()
             .replace('__DECISIONS_PATH__', dec_rel))

    if 'arXiv:2603.15566' not in head:
        i = head.find('\n---\n')      # just before the header's first horizontal rule
        if i == -1:
            head = head.rstrip('\n') + '\n\n' + lore + '\n'
        else:
            head = head[:i] + '\n' + lore + '\n' + head[i:]
        added.append('the Lore paragraph')

    if 'Three levels of a decision' not in head:
        anchor = '**Entry format.**'
        if anchor in head:
            head = head.replace(anchor, three + '\n\n' + anchor, 1)
        else:
            head = head.rstrip('\n') + '\n\n' + three + '\n\n'
        added.append('the three-levels-of-a-decision block')

    if head != orig:
        io.open(ledger, 'w', encoding='utf-8', newline='\n').write(head + sep + tail)
        print('added ' + ', '.join(added))


if __name__ == '__main__':
    main()
