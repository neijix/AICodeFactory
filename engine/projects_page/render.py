"""The page itself (one self-contained HTML file, no network) and the terminal summary."""

from __future__ import annotations

import re
from html import escape

from engine.projects_page.collect import STATUSES

CSS = """
:root{color-scheme:light dark;--bg:#fafafa;--fg:#1c1c1e;--muted:#6b6b70;--line:#e2e2e6;--card:#fff;
--ok:#1a7f37;--warn:#9a6700;--bad:#cf222e;--chip:#eef1f5}
@media (prefers-color-scheme:dark){:root{--bg:#141416;--fg:#ececf0;--muted:#9a9aa2;--line:#2c2c31;
--card:#1c1c20;--ok:#3fb950;--warn:#d29922;--bad:#f85149;--chip:#2a2d33}}
*{box-sizing:border-box}
body{margin:0;font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif;background:var(--bg);color:var(--fg)}
main{max-width:1280px;margin:0 auto;padding:24px 20px 48px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:32px 0 12px}
.meta,.note{color:var(--muted);font-size:13px}
.tiles{display:flex;flex-wrap:wrap;gap:12px;margin:20px 0}
.tile{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 16px;min-width:150px}
.tile b{display:block;font-size:24px;font-variant-numeric:tabular-nums}
.tile span{color:var(--muted);font-size:13px}
.bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:12px}
.bar button{font:inherit;padding:5px 12px;border-radius:6px;border:1px solid var(--line);
background:var(--card);color:var(--fg);cursor:pointer}
.bar button[aria-pressed=true]{border-color:var(--fg);font-weight:600}
.bar input{font:inherit;padding:5px 10px;border-radius:6px;border:1px solid var(--line);
background:var(--card);color:var(--fg);min-width:220px}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:8px}
th,td{text-align:left;vertical-align:top;padding:8px 10px;border-top:1px solid var(--line)}
th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);border-top:0}
td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.name{font-weight:600;white-space:nowrap}.path{color:var(--muted);font-size:12px;word-break:break-all}
.badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:12px;font-weight:600;white-space:nowrap;
border:1px solid currentColor}
.s-ok{color:var(--ok)}.s-stale,.s-off-plan,.s-unfinished{color:var(--warn)}.s-missing{color:var(--bad)}
.chip{display:inline-block;background:var(--chip);border-radius:4px;padding:0 6px;margin:0 4px 4px 0;
font-size:12px;white-space:nowrap}
.chip i{font-style:normal;color:var(--muted);margin-left:4px}
code{font:12px ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.none{color:var(--muted)}tr.unused td{color:var(--muted)}
"""

# Filter and search; the page reads fine without it.
JS = """
const rows=[...document.querySelectorAll('#projects tbody tr')];
let mode='all';
function apply(){const q=document.getElementById('q').value.toLowerCase();
rows.forEach(r=>{const okMode=mode==='all'||(mode==='todo')===(r.dataset.status!=='ok');
r.hidden=!(okMode&&r.textContent.toLowerCase().includes(q));});}
document.querySelectorAll('.bar button').forEach(b=>b.addEventListener('click',()=>{
mode=b.dataset.mode;document.querySelectorAll('.bar button').forEach(x=>x.setAttribute('aria-pressed',x===b));apply();}));
document.getElementById('q').addEventListener('input',apply);
"""


def _chips(items: dict | list, empty: str = "—") -> str:
    if not items:
        return f'<span class="none">{escape(empty)}</span>'
    if isinstance(items, dict):
        return "".join(f'<span class="chip">{escape(k)}<i>×{v}</i></span>' for k, v in items.items())
    return "".join(f'<span class="chip">{escape(k)}</span>' for k in items)


def _step(action: str) -> str:
    """A command in monospace; prose with its slash command in monospace."""
    if not action:
        return '<span class="none">—</span>'
    return re.sub(r"(aicf [^,;]*|/bootstrap-ai)", r"<code>\1</code>", escape(action))


def _project_row(p: dict) -> str:
    used = {k: v["count"] for k, v in sorted(p["skills_used"].items(), key=lambda kv: (-kv[1]["count"], kv[0]))}
    details = []
    if p["placeholder_docs"]:
        details.append("placeholders in " + ", ".join(p["placeholder_docs"]))
    if p["missing_headings"]:
        details.append(f"{len(p['missing_headings'])} AGENTS.md section(s) missing")
    if not p["remote"]:
        details.append("no git remote")
    if p["unpushed"]:
        details.append(f"{p['unpushed']} unpushed commit(s)")
    step = _step(p["action"])
    if details:
        step += f'<div class="note">{escape("; ".join(details))}</div>'
    return (
        f'<tr data-status="{escape(p["status"])}">'
        f'<td><div class="name">{escape(p["name"])}</div><div class="path">{escape(p["path"])}</div></td>'
        f'<td><span class="badge s-{escape(p["status"])}">{escape(p["status_label"])}</span></td>'
        f"<td>{step}</td><td>{_chips(used, 'no use recorded')}</td>"
        f"<td>{_chips(p['local_skills'])}</td><td>{_chips(p['skills_off'])}</td></tr>"
    )


def _skill_row(s: dict) -> str:
    cls = "" if s["uses"] else ' class="unused"'
    off = f'<div class="note">off in {escape(", ".join(s["off_in"]))}</div>' if s["off_in"] else ""
    return (
        f'<tr{cls}><td class="name">{escape(s["name"])}</td><td>{escape(s["source"])}</td>'
        f'<td class="num">{s["uses"]}</td><td>{_chips(s["projects"], "unused")}{off}</td>'
        f'<td class="num">{escape(s["last"][:10]) or "—"}</td></tr>'
    )


def render_html(data: dict) -> str:
    counts = data["summary"]
    tiles = [("total", "Projects")] + [(k, STATUSES[k][0]) for k in STATUSES]
    tile_html = "".join(
        f'<div class="tile"><b class="{"" if k == "total" else "s-" + k}">{counts[k]}</b>'
        f"<span>{escape(label)}</span></div>"
        for k, label in tiles if k == "total" or k == "ok" or counts[k]
    )
    usage_note = data["usage_note"]
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<title>Projects — AICodeFactory</title><style>{CSS}</style></head>
<body><main>
<h1>Projects</h1>
<div class="meta">Code root <code>{escape(data["code_root"])}</code> · generated {escape(data["generated"])}</div>
<div class="tiles">{tile_html}</div>
<h2>Bootstrap status</h2>
<div class="bar">
<button type="button" data-mode="all" aria-pressed="true">All</button>
<button type="button" data-mode="todo" aria-pressed="false">Needs work</button>
<button type="button" data-mode="ok" aria-pressed="false">Bootstrapped</button>
<input id="q" type="search" placeholder="Filter by project or skill" aria-label="Filter projects">
</div>
<table id="projects"><thead><tr><th>Project</th><th>Status</th><th>Next step</th>
<th>Skills used</th><th>Project skills</th><th>Skills off</th></tr></thead>
<tbody>{"".join(_project_row(p) for p in data["projects"])}</tbody></table>
<p class="note">Status comes from <code>aicf doctor --json</code>. A git repo without
<code>AGENTS.md</code> is not bootstrapped; folders that are not git repos are not listed.</p>
<h2>Skills</h2>
<table id="skills"><thead><tr><th>Skill</th><th>Source</th><th>Uses</th><th>Used in</th>
<th>Last used</th></tr></thead><tbody>{"".join(_skill_row(s) for s in data["skills"])}</tbody></table>
<p class="note">{escape(usage_note)}</p>
</main><script>{JS}</script></body></html>
"""


def render_text(data: dict) -> str:
    """The terminal summary: one line per project, need-work first."""
    width = max([len(p["name"]) for p in data["projects"]] + [7])
    lines = [f"Projects in {data['code_root']}"]
    for p in data["projects"]:
        used = ", ".join(sorted(p["skills_used"], key=lambda k: -p["skills_used"][k]["count"])) or "-"
        line = f"  {p['name']:<{width}}  {p['status_label']:<26}  skills: {used}"
        lines.append(line + (f"\n  {'':<{width}}  next: {p['action']}" if p["action"] else ""))
    c = data["summary"]
    lines.append(
        f"{c['total']} project(s): {c['ok']} bootstrapped, {c['missing']} not bootstrapped, "
        f"{c['unfinished']} unfinished, {c['stale'] + c['off-plan']} to refresh"
    )
    return "\n".join(lines)
