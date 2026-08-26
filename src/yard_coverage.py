#!/usr/bin/env python3
"""
YARD documentation coverage checker for Ruby source files.

Identifies documentable anchors (classes, modules, methods, constants) and
determines whether each already has a YARD doc block attached. This is the
primitive that lets the generator send ONLY undocumented code to the AI and
skip files that are already fully documented (zero API cost).

Usage (CLI):
    python src/yard_coverage.py path/to/file.rb          # JSON report for one file
    python src/yard_coverage.py --dir path/to/lib        # summary for a tree
    python src/yard_coverage.py --dir lib --uncovered    # list uncovered anchors
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional

# Lines that are comments but do NOT count as documentation
_DIRECTIVE_PREFIXES = (
    '#!',                       # shebang
    '# frozen_string_literal',
    '# encoding',
    '# coding',
    '# rubocop',
    '# typed:',
)

# Markers that mean "deliberately not documented" - treat as covered so the
# AI never touches them
_SUPPRESSION_MARKERS = (':nodoc:', '@!visibility')

_DEF_RE = re.compile(r'^(\s*)def\s+(?P<name>[^\s(#]+)')
_CLASS_RE = re.compile(r'^(\s*)class\s+(?P<name>[A-Z][A-Za-z0-9_:]*)')
_MODULE_RE = re.compile(r'^(\s*)module\s+(?P<name>[A-Z][A-Za-z0-9_:]*)')
_SINGLETON_CLASS_RE = re.compile(r'^\s*class\s*<<')
_CONSTANT_RE = re.compile(r'^(\s*)(?P<name>[A-Z][A-Z0-9_]*)\s*=\s*(?P<value>.+)$')
_TRIVIAL_CONSTANT_VALUE_RE = re.compile(
    r'^(-?\d[\d_]*(\.\d+)?|true|false|nil|:[a-zA-Z_]\w*|"[^"]{0,40}"|\'[^\']{0,40}\')\s*(#.*)?$'
)
_VISIBILITY_RE = re.compile(r'^(\s*)(private|protected|public)\s*(#.*)?$')
_INLINE_PRIVATE_DEF_RE = re.compile(r'^\s*(private|protected)\s+def\s')


def _is_comment(line: str) -> bool:
    return line.lstrip().startswith('#')


def _is_directive(line: str) -> bool:
    stripped = line.strip()
    return any(stripped.startswith(p) for p in _DIRECTIVE_PREFIXES) or stripped == '#'


def has_doc_block(lines: List[str], idx: int) -> bool:
    """
    Check whether the code line at 0-indexed ``idx`` has a YARD doc block
    (or an explicit suppression marker) attached directly above it.

    A doc block is a contiguous run of comment lines immediately above the
    line (a blank line detaches it, matching YARD semantics). Pure directive
    lines (rubocop, encoding, ...) do not count as documentation on their own.
    """
    i = idx - 1
    found_doc = False
    while i >= 0 and _is_comment(lines[i]):
        stripped = lines[i].strip()
        if any(marker in stripped for marker in _SUPPRESSION_MARKERS):
            return True  # deliberately undocumented - leave alone
        if not _is_directive(lines[i]):
            found_doc = True
        i -= 1
    return found_doc


def find_anchors(content: str) -> List[Dict]:
    """
    Find all documentable anchors in Ruby source.

    Returns a list of dicts:
        {line: int (1-indexed), type: str, name: str, signature: str,
         indent: int, documented: bool}
    """
    lines = content.split('\n')
    anchors: List[Dict] = []
    # visibility per indentation level: {indent: 'private'|'protected'|'public'}
    visibility: Dict[int, str] = {}

    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or _is_comment(line):
            continue

        # Track private/protected/public sections
        vis_match = _VISIBILITY_RE.match(line)
        if vis_match:
            visibility[len(vis_match.group(1))] = vis_match.group(2)
            continue

        # Entering a new class/module scope resets deeper visibility state
        for regex, kind in ((_CLASS_RE, 'class'), (_MODULE_RE, 'module')):
            m = regex.match(line)
            if m and not _SINGLETON_CLASS_RE.match(line):
                indent = len(m.group(1))
                for k in [k for k in visibility if k > indent]:
                    del visibility[k]
                anchors.append({
                    'line': idx + 1,
                    'type': kind,
                    'name': m.group('name'),
                    'signature': stripped,
                    'indent': indent,
                    'documented': has_doc_block(lines, idx),
                })
                break
        else:
            m = _DEF_RE.match(line)
            if m:
                if _INLINE_PRIVATE_DEF_RE.match(line):
                    continue  # private def foo - skip
                indent = len(m.group(1))
                if visibility.get(indent) in ('private', 'protected'):
                    continue  # private section - skip
                anchors.append({
                    'line': idx + 1,
                    'type': 'def',
                    'name': m.group('name'),
                    'signature': stripped.split('#')[0].strip() or stripped,
                    'indent': indent,
                    'documented': has_doc_block(lines, idx),
                })
                continue

            m = _CONSTANT_RE.match(line)
            if m and not _TRIVIAL_CONSTANT_VALUE_RE.match(m.group('value').strip()):
                anchors.append({
                    'line': idx + 1,
                    'type': 'constant',
                    'name': m.group('name'),
                    'signature': stripped[:80],
                    'indent': len(m.group(1)),
                    'documented': has_doc_block(lines, idx),
                })

    return anchors


def find_uncovered_anchors(content: str) -> List[Dict]:
    """Return only the anchors that lack a doc block."""
    return [a for a in find_anchors(content) if not a['documented']]


def coverage_summary(content: str) -> Dict:
    """Return {total, documented, uncovered, coverage_pct} for one file."""
    anchors = find_anchors(content)
    documented = sum(1 for a in anchors if a['documented'])
    total = len(anchors)
    return {
        'total': total,
        'documented': documented,
        'uncovered': total - documented,
        'coverage_pct': round(100.0 * documented / total, 1) if total else 100.0,
    }


def main():
    parser = argparse.ArgumentParser(description='YARD coverage checker for Ruby files')
    parser.add_argument('file', nargs='?', help='Single Ruby file to check')
    parser.add_argument('--dir', help='Check all .rb files under a directory')
    parser.add_argument('--uncovered', action='store_true',
                        help='List uncovered anchors instead of summaries')
    args = parser.parse_args()

    if args.file:
        content = Path(args.file).read_text(encoding='utf-8')
        if args.uncovered:
            print(json.dumps(find_uncovered_anchors(content), indent=2))
        else:
            report = coverage_summary(content)
            report['anchors'] = find_anchors(content)
            print(json.dumps(report, indent=2))
    elif args.dir:
        totals = {'files': 0, 'fully_covered': 0, 'total': 0, 'documented': 0}
        rows = []
        for rb in sorted(Path(args.dir).rglob('*.rb')):
            content = rb.read_text(encoding='utf-8', errors='replace')
            s = coverage_summary(content)
            totals['files'] += 1
            totals['total'] += s['total']
            totals['documented'] += s['documented']
            if s['uncovered'] == 0:
                totals['fully_covered'] += 1
            elif args.uncovered:
                rows.append(f"{rb}: {s['uncovered']} uncovered of {s['total']}")
        for row in rows:
            print(row)
        pct = round(100.0 * totals['documented'] / totals['total'], 1) if totals['total'] else 100.0
        print(f"\n{totals['files']} files, {totals['fully_covered']} fully covered; "
              f"{totals['documented']}/{totals['total']} anchors documented ({pct}%)")
    else:
        parser.error('Provide a file or --dir')


if __name__ == '__main__':
    main()
