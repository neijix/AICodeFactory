#!/usr/bin/env python3
"""Skill evals: does each prompt in tests/skill-evals.json trigger the skill it should?

Each case runs one real `claude -p` turn (at most MAX_TURNS model turns — a model often globs
the folder before it reaches for a skill — in an empty temp folder, with the tools that write or
run things disallowed) and reads which skills the model invoked from the
stream-json output. A case passes when its `expect` skill was invoked — or, for
`"expect": null`, when none of this repo's skills was. The installed skills are what is tested:
on macOS they link to this checkout, on Windows they are copies refreshed by install-global.

Opt-in, never in CI: it needs a signed-in `claude` and costs tokens (a few cents per case on
sonnet). Run it after changing a skill's description.

Usage: uv run tests/skill-evals.py [--model sonnet] [--only <skill>] [--runs N] [--jobs N]
Stdlib only.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DENIED = 'Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Agent'
TIMEOUT = 240
MAX_TURNS = '3'


def invoked_skills(stream):
    """Skill names the turn invoked, from Claude Code's stream-json lines."""
    skills = []
    for line in stream.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('type') != 'assistant':
            continue
        for block in event.get('message', {}).get('content', []):
            if block.get('type') == 'tool_use' and block.get('name') == 'Skill':
                name = str(block.get('input', {}).get('skill', '')).split(':')[-1]
                if name:
                    skills.append(name)
    return skills


def run_case(claude, model, prompt):
    with tempfile.TemporaryDirectory() as cwd:
        cmd = [claude, '-p', prompt, '--output-format', 'stream-json', '--verbose',
               '--max-turns', MAX_TURNS, '--model', model, '--disallowedTools', DENIED]
        try:
            out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT,
                                 encoding='utf-8', errors='replace')
        except subprocess.TimeoutExpired:
            return None, f'timed out after {TIMEOUT}s'
        skills = invoked_skills(out.stdout)
        if not skills and '"type":"result"' not in out.stdout.replace(' ', ''):
            return None, (out.stderr or out.stdout).strip().splitlines()[-1:] or ['no output']
        return skills, ''


def verdict(expect, skills, shipped):
    if expect is None:
        return not (set(skills) & shipped)
    return expect in skills


def load_cases(only, shipped):
    with open(os.path.join(ROOT, 'tests', 'skill-evals.json'), encoding='utf-8') as f:
        cases = json.load(f)['cases']
    if only:
        cases = [c for c in cases if (c['expect'] or 'none') == only]
        if not cases:
            return [], f'no case expects "{only}"'
    for c in cases:
        if c['expect'] is not None and c['expect'] not in shipped:
            return [], f'a case expects "{c["expect"]}", which this repo does not ship'
    return cases, ''


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--model', default='sonnet')
    ap.add_argument('--only', help='run only the cases expecting this skill (use "none" for null)')
    ap.add_argument('--runs', type=int, default=1, help='runs per case (triggering varies)')
    ap.add_argument('--jobs', type=int, default=4)
    args = ap.parse_args()

    claude = shutil.which('claude')
    if not claude:
        print('skill-evals: `claude` is not on PATH — install Claude Code and sign in first')
        return 2
    shipped = set(os.listdir(os.path.join(ROOT, 'skills')))
    cases, problem = load_cases(args.only, shipped)
    if problem:
        print(f'skill-evals: {problem}')
        return 2

    jobs = [(c, r) for c in cases for r in range(args.runs)]
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(lambda j: run_case(claude, args.model, j[0]['prompt']), jobs))

    failed = errored = 0
    for (case, _), (skills, err) in zip(jobs, results):
        want = case['expect'] or 'no skill'
        if skills is None:
            errored += 1
            print(f'ERROR  {want:<20} {case["prompt"][:60]!r}: {err}')
            continue
        ok = verdict(case['expect'], skills, shipped)
        failed += not ok
        print(f'{"PASS " if ok else "FAIL "}  {want:<20} got {", ".join(skills) or "none":<24} {case["prompt"][:50]!r}')
    total = len(jobs)
    print(f'skill-evals ({args.model}): {total - failed - errored}/{total} passed'
          + (f', {failed} failed' if failed else '') + (f', {errored} errored' if errored else ''))
    return 1 if failed or errored else 0


if __name__ == '__main__':
    sys.exit(main())
