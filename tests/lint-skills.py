#!/usr/bin/env python3
"""Lint what this repo ships to every machine: skills, templates and the hook JSON.

Checks (errors fail the run, warnings are counted — list them with --verbose):
  structure    every skills/<dir>/SKILL.md has frontmatter whose `name` equals
               <dir> (lowercase, digits, hyphens, <= 64 chars) and a non-empty `description`
               of <= 1024 chars — the Agent Skills spec limits
  links        every relative markdown link in a skill's .md files resolves from that file's
               folder (a skill is installed as a folder; a broken link is a dead reference)
  size         a skill .md file over SKILL_MD_MAX lines is an error, a SKILL.md over
               SKILL_MD_WARN a warning — every line is context cost; detail goes in references/
  eol          tracked text files are LF (CRLF allowed only in *.ps1 / *.cmd / *.bat)
  ps-encoding  a PowerShell file holding non-ASCII text starts with a UTF-8 BOM: without one,
               Windows PowerShell 5.1 (all a fresh Windows has) reads it as ANSI and fails to
               parse it, so the script dies before it can even hand over to pwsh
  portability  no machine path (/Users/<name>, /home/<name>, X:\\Users\\<name>) in a skill or
               a template — the code root differs per machine, see AGENTS.md
  security     tests/skill-security-patterns.json over skill markdown and hook commands;
               severity high/critical is an error, medium/low a warning
  bare-python  (warning) a skill telling the agent to run `python3 x.py` — write `uv run x.py`:
               on Windows `python3` is often the Store stub, and uv brings the interpreter
  contracts    cross-file promises nothing else checks: every heading listed in
               refresh-agents-sections.py (*_HEADINGS) is a line of templates/AGENTS.md.template (the
               script matches sections by exact text), and every "`x` skill" / "`x` subagent"
               in a skill or template names one this repo ships (or one in KNOWN_EXTERNAL)
  work-material  no tracked file holds an API spec document (OpenAPI / Swagger), a private
               network address or host (PRIVATE_IP / PRIVATE_HOST), a term of the owner's
               private-terms list (found like the engine's pre-commit guard; none = skipped) or
               a work-only skill (`work-*`, or a name holding a private term), and no commit of
               HEAD's history touches a work-only path the remote's default branch no longer has: work-only
               skills and work material belong in a work overlay repo, never here

Suppress a reviewed security hit with `security-allow: <rule-id> <reason>` on the flagged line
or the line directly above it.

Usage: python3 tests/lint-skills.py [--root <repo>] [--verbose]
Stdlib only, so it runs under any python3 / `uv run`.
"""
import json
import os
import re
import subprocess
import sys

CRLF_OK = ('.ps1', '.psm1', '.psd1', '.cmd', '.bat')
POWERSHELL = ('.ps1', '.psm1', '.psd1')
BINARY = ('.png', '.jpg', '.jpeg', '.gif', '.ico', '.icns', '.pdf', '.zip')
MACHINE_PATH = re.compile(r'/Users/(?!<)[A-Za-z0-9._-]+|/home/(?!<)[A-Za-z0-9._-]+|\b[A-Za-z]:\\\\?Users\\\\?(?!<)[A-Za-z0-9._-]+')
NAME_RE = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
ALLOW_RE = re.compile(r'security-allow:\s*([\w-]+)')
BARE_PY = re.compile(r'(?:^|[\s`(])python3?\s+\S+\.py\b')
HEADING_LISTS = re.compile(r'^[A-Z_]*HEADINGS\s*=\s*\[(.*?)^\]', re.M | re.S)
LINK_RE = re.compile(r'\]\(\s*([^)\s]+)[^)]*\)')
SKILL_MD_MAX, SKILL_MD_WARN = 600, 500
REF_RE = re.compile(r'`([a-z0-9]+(?:-[a-z0-9]+)*)` (skill|subagent)s?\b')
# Generic signs of a private network — nobody's in particular, so they can be committed: RFC 1918
# addresses and hosts under a private-use suffix. Docs and tests use the neutral values instead:
# 192.0.2.x (TEST-NET-1) and RFC 2606 names (`example.lan`, `*.test`, `*.invalid`).
PRIVATE_IP = re.compile(r'(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?![\d.])')
PRIVATE_HOST = re.compile(r'\b((?:[a-z0-9-]+\.)+)(?:lan|internal|intranet|corp|home\.arpa)(?![\w(-]|\.\w)', re.IGNORECASE)
NEUTRAL_LABELS = {'example', 'test', 'invalid'}
API_SPEC = re.compile(r'''^\s*\{?\s*["']?(?:openapi|swagger)["']?\s*:''', re.IGNORECASE)
# The owner's private-terms list: never in a repo, found like git-hooks/pre-commit.sh.template.
TERMS_NAME = 'private-terms.txt'
POSIX_CLASSES = {'[:space:]': r'\s', '[:digit:]': r'\d', '[:alpha:]': 'A-Za-z', '[:alnum:]': 'A-Za-z0-9',
                 '[:upper:]': 'A-Z', '[:lower:]': 'a-z', '[:xdigit:]': '0-9A-Fa-f', '[:blank:]': r' \t'}
# Work-only skills live in a work overlay repo, named `work-*` (or holding a private term).
WORK_SKILL = re.compile(r'^work-[a-z0-9-]+$')
REFRESH = 'skills/bootstrap-ai/scripts/refresh-agents-sections.py'
AGENTS_TPL = 'templates/AGENTS.md.template'
# Names a shipped file may cite without this repo shipping them.
KNOWN_EXTERNAL = {
    'general-purpose',  # Claude Code's built-in subagent
}                       # + every work-only name (work_only_name): work overlay skills


def git_files(root):
    out = subprocess.run(['git', '-C', root, 'ls-files', '-z'], capture_output=True, check=True).stdout
    return [f for f in out.decode('utf-8').split('\0') if f]


def read(root, rel):
    with open(os.path.join(root, rel), 'rb') as fh:
        return fh.read()


def encoding_errors(rel, data):
    """eol + ps-encoding over one text file's bytes."""
    low, errors = rel.lower(), []
    if b'\r\n' in data and not low.endswith(CRLF_OK):
        errors.append(f'{rel}: CRLF line endings — convert to LF (.gitattributes forces LF on checkout)')
    if low.endswith(POWERSHELL) and not data.startswith(b'\xef\xbb\xbf') and not data.isascii():
        errors.append(f'{rel}: ps-encoding: non-ASCII text without a UTF-8 BOM — Windows PowerShell 5.1 cannot parse it')
    return errors


def frontmatter(text):
    """Return {key: value} for the top-level scalars of a YAML frontmatter block (enough for
    name/description: plain, quoted, and folded/literal block scalars)."""
    lines = text.replace('\r\n', '\n').split('\n')
    if not lines or lines[0].strip() != '---':
        return None
    try:
        end = lines.index('---', 1)
    except ValueError:
        return None
    fm, key, buf = {}, None, []
    for line in lines[1:end]:
        m = re.match(r'^([A-Za-z_][\w-]*):\s*(.*)$', line)
        if m and not line.startswith(' '):
            if key is not None:
                fm[key] = ' '.join(buf).strip()
            key, val = m.group(1), m.group(2).strip()
            buf = [] if val in ('>', '>-', '|', '|-', '') else [val.strip('"\'')]
        elif key is not None:
            buf.append(line.strip())
    if key is not None:
        fm[key] = ' '.join(buf).strip()
    return fm


def git_out(root, *args):
    return subprocess.run(['git', '-C', root, *args], capture_output=True, text=True).stdout.strip()


def private_terms_file(root):
    """$AI_PRIVATE_TERMS_FILE (empty or `none` = no check), <code root>/.ai-root/private-terms.txt
    (code root: the folder holding the repo's top level), ~/.private-terms — first found wins."""
    if 'AI_PRIVATE_TERMS_FILE' in os.environ:
        raw = os.environ['AI_PRIVATE_TERMS_FILE']
        if raw in ('', 'none'):
            return None
        if os.path.isfile(raw):
            return raw
        print(f'lint-skills: AI_PRIVATE_TERMS_FILE={raw} not found - private terms unchecked', file=sys.stderr)
        return None
    top = git_out(root, 'rev-parse', '--show-toplevel')
    candidates = [os.path.join(os.path.dirname(top), '.ai-root', TERMS_NAME)] if top else []
    home = os.environ.get('HOME') or os.environ.get('USERPROFILE') or os.path.expanduser('~')
    candidates.append(os.path.join(home, '.private-terms'))
    return next((path for path in candidates if os.path.isfile(path)), None)


def private_terms(path):
    """Compiled terms: a line is a case-insensitive substring, `re:<pattern>` a POSIX ERE."""
    if path is None:
        return []
    with open(path, encoding='utf-8-sig', errors='replace') as fh:
        lines = [line.strip() for line in fh.read().replace('\r', '').splitlines()]
    terms = []
    for line in lines:
        if not line or line.startswith('#'):
            continue
        pattern = line[3:] if line.startswith('re:') else re.escape(line)
        for posix, python in POSIX_CLASSES.items():
            pattern = pattern.replace(posix, python)
        try:
            terms.append(re.compile(pattern, re.IGNORECASE))
        except re.error:
            print(f'lint-skills: invalid regex in {path} skipped: {line}', file=sys.stderr)
    return terms


def private_network(line):
    """The first RFC 1918 address or private-use host name on the line, else None."""
    m = PRIVATE_IP.search(line)
    if m:
        return f'private-network address "{m.group(0)}"'
    for m in PRIVATE_HOST.finditer(line):
        if not NEUTRAL_LABELS & set(m.group(1).lower().split('.')):
            return f'private-network host "{m.group(0)}"'
    return None


def work_content_errors(rel, data, terms):
    """work-material, by content: a private term, a private network, or an API spec document."""
    for n, line in enumerate(data.decode('utf-8', errors='replace').splitlines(), 1):
        term = next((m for m in (t.search(line) for t in terms) if m), None)
        what = (f'private term "{term.group(0)}"' if term else private_network(line)
                or ('an API spec document' if API_SPEC.search(line) else None))
        if what:
            return [f'{rel}:{n}: work-material — {what}: this repo never holds work or private'
                    ' material; it belongs in a work overlay repo (README "Work-only services")']
    return []


def work_only_name(name, terms):
    return bool(WORK_SKILL.match(name)) or any(t.search(name) for t in terms)


def work_only_path(rel, terms):
    """A skill folder named like a work-only skill, or any shipped global path (skills/,
    templates/global/, and their old home vscode-global/) naming a private term."""
    parts = rel.split('/')
    if parts[0] == 'vscode-global':
        parts = parts[1:]
    elif parts[:2] == ['templates', 'global']:
        parts = parts[2:]
    elif parts[0] != 'skills':
        return False
    if len(parts) > 2 and parts[0] == 'skills' and WORK_SKILL.match(parts[1]):
        return True
    return any(t.search(part) for part in parts for t in terms)


def history_hit(root, ref, terms):
    """Newest commit of `ref` touching a work-only path, or ''."""
    out = git_out(root, 'log', '--name-only', '--format=%x00%h', ref, '--',
                  'skills/', 'templates/global/', 'vscode-global/')
    commit = ''
    for line in out.splitlines():
        if line.startswith('\0'):
            commit = line[1:]
        elif line and work_only_path(line, terms):
            return commit
    return ''


def work_only_errors(root, files, terms):
    """work-material, by path: a work-only skill tracked here, or back in the history (a
    merge from a clone made before the purge brings the old commits, specs included, back)."""
    errors = []
    for rel in files:
        if work_only_path(rel, terms):
            errors.append(f'{rel}: work-material — a work-only skill or path: it lives in a work overlay'
                          ' repo (README "Work-only services"), never here')
    # Only once the remote's default branch is clean, so the check holds from the purge on.
    if git_out(root, 'rev-parse', '--is-shallow-repository') == 'false':
        hit = history_hit(root, 'HEAD', terms)
        base = next((r for r in ('refs/remotes/origin/HEAD', 'refs/remotes/origin/main', 'refs/remotes/origin/master')
                     if git_out(root, 'rev-parse', '--verify', '-q', r)), '')
        if hit and not (base and history_hit(root, base, terms)):
            errors.append(f'history: work-material — commit {hit} holds a purged work-only path: this branch'
                          ' descends from the history rewritten to drop them. Never merge or push it;'
                          ' re-apply its own commits onto the current default branch of the remote (KNOWLEDGE.md)')
    return errors


def check_structure(root, errors):
    skills_dir = os.path.join(root, 'skills')
    for d in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, d)
        if not os.path.isdir(path):
            continue
        rel = f'skills/{d}/SKILL.md'
        if not os.path.isfile(os.path.join(root, rel)):
            errors.append(f'{rel}: missing')
            continue
        fm = frontmatter(read(root, rel).decode('utf-8'))
        if fm is None:
            errors.append(f'{rel}: no frontmatter')
            continue
        name, desc = fm.get('name', ''), fm.get('description', '')
        if name != d:
            errors.append(f'{rel}: name "{name}" does not match folder "{d}"')
        if not NAME_RE.match(d) or len(d) > 64:
            errors.append(f'{rel}: folder name must be lowercase-hyphenated, <= 64 chars')
        if not desc:
            errors.append(f'{rel}: empty description')
        elif len(desc) > 1024:
            errors.append(f'{rel}: description is {len(desc)} chars (max 1024)')


def check_links_and_size(root, files, errors, warnings):
    for rel in files:
        if not (rel.startswith('skills/') and rel.endswith('.md')):
            continue
        if not os.path.isfile(os.path.join(root, rel)):
            continue
        md = read(root, rel).decode('utf-8', errors='replace').splitlines()
        if len(md) > SKILL_MD_MAX:
            errors.append(f'{rel}: {len(md)} lines (max {SKILL_MD_MAX}) — move detail to references/')
        elif rel.endswith('/SKILL.md') and len(md) > SKILL_MD_WARN:
            warnings.append(f'{rel}: {len(md)} lines (over {SKILL_MD_WARN}) — move detail to references/')
        base = os.path.dirname(rel)
        for n, line in enumerate(md, 1):
            for target in LINK_RE.findall(line):
                target = target.strip('<>').split('#', 1)[0]
                if not target or re.match(r'^[a-z][a-z0-9+.-]*:', target, re.I) or target.startswith('/'):
                    continue
                if not os.path.exists(os.path.normpath(os.path.join(root, base, target))):
                    errors.append(f'{rel}:{n}: link "{target}" does not resolve')


def check_headings(root, errors):
    """contracts: every heading refresh-agents-sections.py matches is a line of AGENTS.md.template."""
    if os.path.isfile(os.path.join(root, REFRESH)) and os.path.isfile(os.path.join(root, AGENTS_TPL)):
        lists = HEADING_LISTS.findall(read(root, REFRESH).decode('utf-8'))
        headings = [h for body in lists for h in re.findall(r'"([^"]+)"', body)]
        if not headings:
            errors.append(f'{REFRESH}: no *_HEADINGS list found — the heading contract is unchecked')
        tpl_lines = {l.rstrip() for l in read(root, AGENTS_TPL).decode('utf-8').splitlines()}
        for h in headings:
            if h not in tpl_lines:
                errors.append(f'{AGENTS_TPL}: heading "{h}" (listed in refresh-agents-sections.py) is gone'
                              ' — every project would report it MISSING; change both together')


def check_references(root, files, terms, errors):
    """contracts: every "`x` skill" / "`x` subagent" names one this repo ships, or a known external."""
    agents_dir = os.path.join(root, 'templates', '.claude', 'agents')
    shipped = {
        'skill': set(os.listdir(os.path.join(root, 'skills'))),
        'subagent': {f[:-len('.md.template')] for f in os.listdir(agents_dir) if f.endswith('.md.template')}
        if os.path.isdir(agents_dir) else set(),
    }
    for rel in files:
        if not (rel.startswith('skills/') and rel.endswith('.md') or rel.endswith('.template')):
            continue
        if not os.path.isfile(os.path.join(root, rel)):
            continue
        for n, line in enumerate(read(root, rel).decode('utf-8', errors='replace').splitlines(), 1):
            for name, kind in REF_RE.findall(line):
                if name not in KNOWN_EXTERNAL and not work_only_name(name, terms) and name not in shipped[kind]:
                    errors.append(f'{rel}:{n}: names the `{name}` {kind}, which this repo does not ship')


def main():
    args = sys.argv[1:]
    verbose = '--verbose' in args
    root = args[args.index('--root') + 1] if '--root' in args else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rules = [dict(r, rx=re.compile(r['regex'], re.IGNORECASE)) for r in
             json.load(open(os.path.join(root, 'tests', 'skill-security-patterns.json'), encoding='utf-8'))['rules']]
    files = git_files(root)
    terms = private_terms(private_terms_file(root))
    errors, warnings = work_only_errors(root, files, terms), []

    check_structure(root, errors)
    check_links_and_size(root, files, errors, warnings)

    # eol + work-material + portability + security
    for rel in files:
        low = rel.lower()
        if low.endswith(BINARY) or not os.path.isfile(os.path.join(root, rel)):
            continue
        data = read(root, rel)
        errors += work_content_errors(rel, data, terms)
        if b'\0' in data:
            continue
        errors += encoding_errors(rel, data)
        shipped = rel.startswith('skills/') or '.template' in rel
        if not shipped:
            continue
        text = data.decode('utf-8', errors='replace')
        lines = text.replace('\r\n', '\n').split('\n')
        for n, line in enumerate(lines, 1):
            m = MACHINE_PATH.search(line)
            if m:
                errors.append(f'{rel}:{n}: machine path "{m.group(0)}" — use $AI_CODE_ROOT / ~ / a placeholder')
        if low.endswith('settings.json.template'):
            targets = [(n, l) for n, l in enumerate(lines, 1) if '"command"' in l]
            scoped = [r for r in rules if r['category'] == 'dangerous-shell']
        elif rel.startswith('skills/') and low.endswith('.md'):
            targets = list(enumerate(lines, 1))
            scoped = rules
        else:
            continue
        for n, line in targets:
            if scoped is rules and BARE_PY.search(line):
                warnings.append(f'{rel}:{n}: bare-python — write `uv run <script>.py`')
            allowed = set(ALLOW_RE.findall(line)) | (set(ALLOW_RE.findall(lines[n - 2])) if n > 1 else set())
            for r in scoped:
                if r['id'] in allowed or not r['rx'].search(line):
                    continue
                msg = f'{rel}:{n}: [{r["severity"]}] {r["id"]} — {r["message"]}'
                (errors if r['severity'] in ('high', 'critical') else warnings).append(msg)

    check_headings(root, errors)
    check_references(root, files, terms, errors)

    for e in errors:
        print(f'ERROR {e}')
    if verbose:
        for w in warnings:
            print(f'warn  {w}')
    print(f'lint-skills: {len(errors)} error(s), {len(warnings)} warning(s)'
          + ('' if verbose or not warnings else ' — --verbose lists the warnings'))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
