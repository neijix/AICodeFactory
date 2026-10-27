#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["lizard>=1.17"]
# ///
"""Structural health of a repo: oversized files, oversized or tangled functions, copy-paste.

  report    the hotspots, worst first (no baseline needed)
  check     gate: exit 1 when a file, function or duplicated block is new over a limit or grew
            past its recorded size (no .code-health.json: its size at HEAD) — existing debt passes
  baseline  record the current offenders in .code-health.json: the first run grandfathers
            everything; later runs only tighten (drop fixed entries, lower shrunk ones) unless
            --accept, which also records new and grown ones (a human decision)

Limits (override under "limits" in .code-health.json): file_lines 800, function_lines 80,
function_ccn 20 (cyclomatic complexity), duplicate_lines 10 (a block of that many significant
lines found twice counts as a copy). "exclude" takes extra glob patterns.

Usage: uv run code_health.py report|check|baseline [--root DIR] [--top N] [--json] [--accept]
"""
import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from itertools import combinations

CONFIG = '.code-health.json'
LIMITS = {'file_lines': 800, 'function_lines': 80, 'function_ccn': 20, 'duplicate_lines': 10}
METRICS = ('file_lines', 'function_lines', 'function_ccn', 'duplicate_lines')
CODE_EXT = {
    '.py', '.js', '.mjs', '.cjs', '.jsx', '.ts', '.tsx', '.vue', '.svelte', '.swift', '.go',
    '.rs', '.java', '.kt', '.kts', '.cs', '.c', '.h', '.cc', '.cpp', '.hpp', '.m', '.mm',
    '.rb', '.php', '.lua', '.scala', '.dart', '.sh', '.bash', '.zsh', '.ps1', '.psm1',
    '.css', '.scss', '.less', '.html', '.htm', '.sql', '.gd',
}
EXCLUDE = [
    '*.min.js', '*.min.css', '*.bundle.js', '*.map', '*-lock.*', '*.lock', '*.pb.go',
    '*_pb2.py', '*.g.dart', '*.generated.*', 'node_modules/*', '*/node_modules/*', 'vendor/*',
    '*/vendor/*', 'third_party/*', 'dist/*', 'build/*', '*/dist/*', '*/build/*', '*.egg-info/*',
    '.venv/*', '*/migrations/*',
]
# Lines that are the same everywhere by nature: never evidence of a copy.
TRIVIAL = re.compile(r'^(?:import\s|from\s+\S+\s+import\s|#include|using\s|package\s|require\(|'
                     r'(?:#|//|/\*|\*|<!--|-->|--\s))')


def git(root, *args, data=None):
    return subprocess.run(['git', '-C', root, *args], input=data, capture_output=True).stdout


def wanted(rel, patterns):
    return (os.path.splitext(rel)[1].lower() in CODE_EXT
            and not any(fnmatch.fnmatch(rel, p) for p in patterns))


def work_tree(root, patterns):
    """(rel, bytes) of tracked and untracked-not-ignored source files on disk."""
    names = git(root, 'ls-files', '-z') + git(root, 'ls-files', '-z', '--others', '--exclude-standard')
    for rel in sorted({f for f in names.decode('utf-8', 'replace').split('\0') if f}):
        path = os.path.join(root, rel)
        if wanted(rel, patterns) and os.path.isfile(path):   # not deleted in the work tree
            with open(path, 'rb') as fh:
                yield rel, fh.read()


def head_tree(root, patterns):
    """(rel, bytes) of the same files as committed at HEAD — the baseline when none is recorded."""
    names = [f for f in git(root, 'ls-tree', '-r', '-z', '--name-only', 'HEAD').decode('utf-8', 'replace')
             .split('\0') if f and wanted(f, patterns)]
    out = git(root, 'cat-file', '--batch', data=''.join('HEAD:%s\n' % n for n in names).encode('utf-8'))
    pos = 0
    for rel in names:
        end = out.index(b'\n', pos)
        header = out[pos:end].split()
        if len(header) < 3 or header[1] != b'blob':
            pos = end + 1
            continue
        size = int(header[2])
        yield rel, out[end + 1:end + 1 + size]
        pos = end + 1 + size + 1


def load_config(root):
    path = os.path.join(root, CONFIG)
    if not os.path.isfile(path):
        return None
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def candidates(root, config, at_head=False):
    patterns = EXCLUDE + list((config or {}).get('exclude', []))
    for rel, raw in (head_tree if at_head else work_tree)(root, patterns):
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            continue
        lines = text.splitlines()
        if lines and len(text) / len(lines) > 300:
            continue                                    # minified or generated
        yield rel, text, lines


def functions(rel, text):
    import lizard
    import lizard_languages
    if lizard_languages.get_reader_for(rel) is None:   # lizard would parse it as C
        return []
    try:
        info = lizard.analyze_file.analyze_source_code(rel, text)
    except Exception:                                   # a parser crash must not stop the run
        return []
    return [(f.name, f.start_line, f.length, f.cyclomatic_complexity) for f in info.function_list]


def significant(lines):
    """[(line number, normalized text)] of the lines that can be evidence of a copy."""
    keep = []
    for no, line in enumerate(lines, 1):
        s = ' '.join(line.split())
        if sum(c.isalnum() for c in s) >= 3 and not TRIVIAL.match(s):
            keep.append((no, s))
    return keep


def copies(sig, window):
    """Each window of `window` significant lines seen at 2-20 places that do not overlap."""
    seen = defaultdict(list)
    for rel, keep in sig.items():
        for i in range(len(keep) - window + 1):
            seen['\n'.join(s for _, s in keep[i:i + window])].append((rel, i))
    for occ in seen.values():
        if 2 <= len(occ) <= 20:                         # >20 copies: boilerplate, not a paste
            real = [o for o in occ if any(p[0] != o[0] or abs(p[1] - o[1]) >= window
                                          for p in occ if p != o)]
            if real:
                yield real


def duplicates(files, window):
    """files: {rel: [lines]} -> ({rel: duplicated line count}, {(a, b): [lines in a, a line, b line]})."""
    sig = {rel: significant(lines) for rel, lines in files.items()}
    covered = defaultdict(set)
    pairs = {}
    for real in copies(sig, window):
        for rel, i in real:
            covered[rel].update(no for no, _ in sig[rel][i:i + window])
        for (a, ia), (b, ib) in combinations(sorted(real), 2):
            if a != b:
                entry = pairs.setdefault((a, b), [set(), sig[a][ia][0], sig[b][ib][0]])
                entry[0].update(no for no, _ in sig[a][ia:ia + window])
    return ({rel: len(v) for rel, v in covered.items()},
            {k: [len(v[0]), v[1], v[2]] for k, v in pairs.items()})


def measure(root, config, at_head=False):
    limits = dict(LIMITS, **(config or {}).get('limits', {}))
    found = {m: {} for m in METRICS}
    where = {}
    texts = {}
    for rel, text, lines in candidates(root, config, at_head):
        texts[rel] = lines
        if len(lines) > limits['file_lines']:
            found['file_lines'][rel] = len(lines)
        for name, start, length, ccn in functions(rel, text):
            key = '%s::%s' % (rel, name)
            for metric, value in (('function_lines', length), ('function_ccn', ccn)):
                if value > limits[metric] and value > found[metric].get(key, 0):
                    found[metric][key] = value
                    where[key] = start
    dup, pairs = duplicates(texts, limits['duplicate_lines'])
    found['duplicate_lines'] = {rel: n for rel, n in dup.items()}
    return limits, found, where, pairs


def cmd_report(root, config, top, as_json):
    limits, found, where, pairs = measure(root, config)
    worst_pairs = sorted(pairs.items(), key=lambda kv: -kv[1][0])[:top]
    if as_json:
        print(json.dumps({'limits': limits, 'offenders': found,
                          'copies': [{'a': a, 'b': b, 'lines': v[0], 'a_line': v[1], 'b_line': v[2]}
                                     for (a, b), v in worst_pairs]}, indent=2))
        return 0
    titles = {'file_lines': 'Files over %d lines', 'function_lines': 'Functions over %d lines',
              'function_ccn': 'Functions over complexity %d', 'duplicate_lines': 'Duplicated lines per file (blocks of %d+)'}
    for metric in METRICS:
        rows = sorted(found[metric].items(), key=lambda kv: -kv[1])
        print('%s: %d' % (titles[metric] % limits[metric], len(rows)))
        for key, value in rows[:top]:
            print('  %7d  %s' % (value, key if key not in where else '%s (line %d)' % (key, where[key])))
    print('Copies between files (top %d):' % top)
    for (a, b), (n, la, lb) in worst_pairs:
        print('  %7d  %s:%d  <->  %s:%d' % (n, a, la, b, lb))
    return 0


def cmd_check(root, config):
    limits, found, where, _ = measure(root, config)
    if config is None:                                  # no record: never worse than the last commit
        base = measure(root, config, at_head=True)[1]
        print('code-health: no %s, comparing with HEAD (run `baseline` once to record the debt)' % CONFIG)
    else:
        base = config.get('baseline', {})
    bad, better = [], []
    for metric in METRICS:
        known = base.get(metric, {})
        for key, value in sorted(found[metric].items()):
            if key not in known:
                bad.append('new      %-15s %6d > %d  %s' % (metric, value, limits[metric], key))
            elif value > known[key]:
                bad.append('grew     %-15s %6d (was %d)  %s' % (metric, value, known[key], key))
        better += [key for key, value in known.items() if found[metric].get(key, 0) < value]
    if better and config is not None:
        print('code-health: %d recorded offender(s) improved — run `baseline` to lock the gain in' % len(better))
    if not bad:
        print('code-health: OK (%d file(s), %d function(s) over a limit; none new, none grew)'
              % (len(found['file_lines']), len(found['function_lines'])))
        return 0
    print('code-health: FAIL — %d structural regression(s):' % len(bad))
    for line in bad:
        print('  ' + line)
    print('Fix: split the file or extract the function / shared module (code-health skill). '
          'A rename or a deliberate exception: `baseline --accept`, with the user\'s ok.')
    return 1


def cmd_baseline(root, config, accept):
    limits, found, _, _ = measure(root, config)
    first = config is None
    config = config or {}
    base = config.get('baseline', {})
    new_base = {}
    for metric in METRICS:
        known = base.get(metric, {})
        keep = {}
        for key, value in found[metric].items():
            if first or accept:
                keep[key] = value
            elif key in known:
                keep[key] = min(value, known[key])
        new_base[metric] = dict(sorted(keep.items()))
    config['limits'] = dict(LIMITS, **config.get('limits', {}))
    config.setdefault('exclude', [])
    config['baseline'] = new_base
    with open(os.path.join(root, CONFIG), 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(config, fh, indent=2)
        fh.write('\n')
    print('code-health: %s %s (%s)' % ('wrote' if first else 'updated', CONFIG,
                                       ', '.join('%s %d' % (m, len(new_base[m])) for m in METRICS)))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('report', 'check', 'baseline'))
    ap.add_argument('--root', help='repo root (default: the git top level of the current directory)')
    ap.add_argument('--top', type=int, default=15)
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--accept', action='store_true', help='baseline: also record new and grown offenders')
    args = ap.parse_args()
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    root = args.root or subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True,
                                       text=True).stdout.strip()
    if not root:
        sys.exit('code-health: not in a git repo — run it from the project, or pass --root')
    config = load_config(root)
    if args.command == 'report':
        return cmd_report(root, config, args.top, args.json)
    if args.command == 'check':
        return cmd_check(root, config)
    return cmd_baseline(root, config, args.accept)


if __name__ == '__main__':
    sys.exit(main())
