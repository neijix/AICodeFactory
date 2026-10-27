#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["websockets>=13"]
# ///
"""ui_doctor — check a web project's UI against the rules a script can check, like doctor does
for the AI setup: one line per rule, OK / FIX / WARN / SKIP, nothing written.

    uv run ui_doctor.py [PATH]                         # static: scan the sources under PATH (default .)
    uv run ui_doctor.py [PATH] --url http://127.0.0.1:3000/ [--wait-for JS] [--shots DIR]
    uv run ui_doctor.py --no-static --url URL --json   # live only, one JSON document on stdout

Static rules read HTML, JSX/TSX, Vue, Svelte, Astro and template files plus CSS/SCSS/LESS:
document basics (lang, viewport, zoom, title), images, names and labels, keyboard traps of the
markup kind, motion and focus CSS, mobile viewport units, fonts and token sprawl. --url also loads
the page in headless Chrome (the headless-ui-smoke skill's driver) and measures what only a
browser knows: contrast in light and dark, unnamed controls, small targets, headings, reflow at
320px, inputs that zoom on iOS, layout shift, motion under reduced-motion, invisible focus.

  OK    the rule holds          FIX   it breaks: fix the listed places (exit 1)
  WARN  worth a look, maybe intended            SKIP  nothing to check it on
Exit 0 when nothing is FIX, 1 otherwise, 2 on bad usage or when Chrome cannot be driven.
A clean run is not a good UI: about half of real problems need eyes — see SKILL.md.
"""
from __future__ import annotations

import argparse
import bisect
import contextlib
import json
import os
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

MARKUP = {".html", ".htm", ".jsx", ".tsx", ".vue", ".svelte", ".astro", ".hbs", ".njk", ".ejs",
          ".jinja", ".j2", ".erb", ".liquid", ".twig", ".php", ".cshtml", ".razor"}
COMPONENT = {".jsx", ".tsx", ".vue", ".svelte"}   # frameworks that inject viewport/title themselves
STYLE = {".css", ".scss", ".sass", ".less"}
SCRIPT = {".js", ".mjs", ".cjs", ".ts"}
SKIP_DIRS = {"node_modules", ".git", "dist", "build", "out", ".next", ".nuxt", ".svelte-kit",
             ".astro", ".output", "coverage", "vendor", "venv", ".venv", "__pycache__", "target",
             "bin", "obj", ".cache", ".turbo", "storybook-static"}
MAX_BYTES = 1_000_000


def _tag(name: str) -> re.Pattern:
    """An opening tag; quoted values and one level of nested JSX braces may hold '>'."""
    body = r"""(?:[^>"'{]|"[^"]*"|'[^']*'|\{(?:[^{}]|\{[^{}]*\})*\})*"""
    return re.compile(rf"<{name}\b{body}>", re.S)


IMG, HTML, META = _tag("img"), _tag("html"), _tag("meta")
FIELD = _tag("(?:input|select|textarea)")
CLICKABLE = _tag("(?:div|span|li|td|tr|img|p|section|article)")
SCRIPT_SRC, LINK = _tag("script"), _tag("link")
BUTTON_EL = re.compile(r"(<button\b(?:[^>\"'{]|\"[^\"]*\"|'[^']*'|\{(?:[^{}]|\{[^{}]*\})*\})*>)(.*?)</button>", re.S | re.I)
LINK_EL = re.compile(r"(<a\b(?:[^>\"'{]|\"[^\"]*\"|'[^']*'|\{(?:[^{}]|\{[^{}]*\})*\})*>)(.*?)</a>", re.S)


def has_attr(tag: str, *names: str) -> bool:
    return any(re.search(rf"(?<![\w:.-]){re.escape(n)}(?:\s*=|[\s/>])", tag, re.I) for n in names)


def attr(tag: str, name: str) -> str:
    m = re.search(rf"""(?<![\w:.-]){re.escape(name)}\s*=\s*(?:"([^"]*)"|'([^']*)'|\{{["'`]?([^}}"'`]*)|([^\s>]+))""", tag, re.I)
    return next((g for g in m.groups() if g is not None), "") if m else ""


def spread(tag: str) -> bool:
    """A JSX {...props} or Vue v-bind="obj" may carry any attribute: the rule cannot judge it."""
    return "{..." in tag or re.search(r"\sv-bind\s*=", tag) is not None


@dataclass
class Source:
    rel: str
    suffix: str
    text: str
    _lines: list[int] = field(default_factory=list)

    def line(self, index: int) -> int:
        if not self._lines:
            self._lines = [i for i, ch in enumerate(self.text) if ch == "\n"]
        return bisect.bisect_left(self._lines, index) + 1

    @property
    def markup(self) -> bool:
        return self.suffix in MARKUP

    @property
    def document(self) -> bool:
        return self.markup and re.search(r"<html\b|<!doctype", self.text, re.I) is not None


def collect(root: Path) -> list[Source]:
    sources = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            path = Path(dirpath) / name
            suffix = path.suffix.lower()
            if suffix not in MARKUP | STYLE | SCRIPT or ".min." in name or path.stat().st_size > MAX_BYTES:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            sources.append(Source(path.relative_to(root).as_posix(), suffix, text))
    return sources


# --- static rules: each yields (index, detail) for one source ------------------------------------

def r_img_alt(src):
    for m in IMG.finditer(src.text):
        if not has_attr(m.group(), "alt") and not spread(m.group()):
            yield m.start(), ""


def r_img_size(src):
    for m in IMG.finditer(src.text):
        tag = m.group()
        if not (has_attr(tag, "width") and has_attr(tag, "height")) and not spread(tag) and "aspect-ratio" not in tag:
            yield m.start(), ""


def r_tabindex(src):
    for m in re.finditer(r"""tabindex\s*=\s*["'{]?\s*([1-9]\d*)""", src.text, re.I):
        yield m.start(), f"tabindex={m.group(1)}"


def r_click_div(src):
    for m in CLICKABLE.finditer(src.text):
        tag = m.group()
        if re.search(r"(?<![\w-])(?:onclick|@click|on:click|v-on:click|\(click\))\s*=", tag, re.I) and not has_attr(tag, "role"):
            yield m.start(), tag.split()[0][1:]


def _no_name(tag: str, inner: str) -> bool:
    if has_attr(tag, "aria-label", "aria-labelledby", "title", ":aria-label") or spread(tag):
        return False
    if re.search(r"<img\b[^>]*\balt\s*=\s*[\"'][^\"']+", inner) or re.search(r"<title>\s*\S", inner):
        return False
    visible = re.sub(r"<[^>]*>", "", inner)
    return not visible.strip() and "{" not in inner


def r_button_name(src):
    for m in BUTTON_EL.finditer(src.text):
        if _no_name(m.group(1), m.group(2)):
            yield m.start(), "icon-only button"


def r_link_name(src):
    for m in LINK_EL.finditer(src.text):
        if _no_name(m.group(1), m.group(2)):
            yield m.start(), "empty link"


def r_field_label(src):
    text = src.text
    ids = set(re.findall(r"""(?:\bfor|htmlFor)\s*=\s*\{?["']([^"']+)""", text))
    for m in FIELD.finditer(text):
        tag = m.group()
        kind = attr(tag, "type").lower()
        if kind in {"hidden", "submit", "button", "reset", "image"} or spread(tag):
            continue
        if has_attr(tag, "aria-label", "aria-labelledby", "title") or attr(tag, "id") in ids:
            continue
        if text.rfind("<label", 0, m.start()) > text.rfind("</label>", 0, m.start()):
            continue   # wrapped in a <label>
        yield m.start(), "only a placeholder" if has_attr(tag, "placeholder") else "no label"


def r_paste(src):
    for m in re.finditer(r"""on[Pp]aste|['"]paste['"]""", src.text):
        if "preventDefault" in src.text[max(0, m.start() - 300): m.end() + 300]:
            yield m.start(), ""


def _viewport(src):
    for m in META.finditer(src.text):
        if attr(m.group(), "name").lower() == "viewport":
            return m
    return None


def r_zoom(src):
    m = _viewport(src)
    content = attr(m.group(), "content").lower().replace(" ", "") if m else ""
    if re.search(r"user-scalable=(no|0)|maximum-scale=1(\.0*)?(,|$)", content):
        yield m.start(), content


def r_lang(src):
    m = HTML.search(src.text)
    if m and not has_attr(m.group(), "lang") and not spread(m.group()):
        yield m.start(), ""


def r_viewport(src):
    if src.suffix not in COMPONENT and HTML.search(src.text) and not _viewport(src):
        yield 0, ""


def r_title(src):
    if src.suffix not in COMPONENT and HTML.search(src.text) and not re.search(r"<title\b", src.text, re.I):
        yield 0, ""


def r_third_party(src):
    for pattern, key in ((SCRIPT_SRC, "src"), (LINK, "href")):
        for m in pattern.finditer(src.text):
            tag, url = m.group(), attr(m.group(), key)
            if key == "href" and "stylesheet" not in attr(tag, "rel").lower():
                continue
            if re.match(r"(https?:)?//", url) and not has_attr(tag, "integrity"):
                yield m.start(), url[:80]


def r_outline(src):
    for m in re.finditer(r"outline\s*:\s*(?:none|0)\b|(?<![\w:-])outline-none\b", src.text):
        yield m.start(), ""


def r_transition_all(src):
    for m in re.finditer(r"transition(?:-property)?\s*:\s*all\b|(?<![\w-])transition-all\b", src.text):
        yield m.start(), ""


LAYOUT_PROPS = r"(?:width|height|top|left|right|bottom|margin(?:-\w+)?|padding(?:-\w+)?)"


def _blocks(text: str, opener: str):
    """(start, body) of every `opener … { … }` block, braces matched."""
    for m in re.finditer(opener, text):
        depth, i = 0, text.find("{", m.end() - 1)
        for j in range(i, len(text)):
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            if depth == 0:
                yield m.start(), text[i + 1: j]
                break


def r_layout_animation(src):
    for start, body in _blocks(src.text, r"@keyframes\s+[\w-]+\s*\{"):
        props = sorted(set(re.findall(rf"(?<![\w-]){LAYOUT_PROPS}\s*:", body)))
        if props:
            yield start, "keyframes animate " + ", ".join(p.rstrip(": ") for p in props)
    for m in re.finditer(rf"transition(?:-property)?\s*:[^;{{}}]*(?<![\w-]){LAYOUT_PROPS}(?![\w-])", src.text):
        yield m.start(), "transition on a layout property"


def r_vh(src):
    if re.search(r"\b\d+(?:dvh|svh|lvh)\b|fill-available|(?<![\w-])h-dvh\b", src.text):
        return
    for m in re.finditer(r"\b100vh\b|(?<![\w:-])(?:min-)?h-screen\b", src.text):
        yield m.start(), m.group()


def r_tiny_font(src):
    for m in re.finditer(r"font-size\s*:\s*(\d*\.?\d+)(px|rem)\b|(?<![\w-])text-\[(\d*\.?\d+)(px|rem)\]", src.text):
        value, unit = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(4))
        px = float(value) * (16 if unit == "rem" else 1)
        if 0 < px < 12:
            yield m.start(), f"{value}{unit}"


def r_font_display(src):
    for start, body in _blocks(src.text, r"@font-face\s*\{"):
        if "font-display" not in body:
            yield start, ""


def r_select_none(src):
    for m in re.finditer(r"(^|[}\s])((?:html|body|\*|:root)\s*(?:,[^{]*)?)\{([^{}]*)\}", src.text):
        if re.search(r"user-select\s*:\s*none", m.group(3)):
            yield m.start(2), m.group(2).strip()


@dataclass(frozen=True)
class Rule:
    id: str
    section: str
    scope: str           # markup | style (CSS files + markup) | code (markup + JS/TS)
    status: str
    what: str
    hint: str
    find: object


RULES = [
    Rule("html-lang", "Document", "markup", "FIX", "<html> has a lang attribute", "<html lang=\"en\"> (WCAG 3.1.1; screen readers pick the voice from it)", r_lang),
    Rule("viewport", "Document", "markup", "FIX", "pages have a viewport meta", "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"> (mobile-web skill §1)", r_viewport),
    Rule("zoom-blocked", "Document", "markup", "FIX", "pinch-zoom is not disabled", "drop user-scalable=no / maximum-scale=1 (WCAG 1.4.4); fix input zoom with 16px inputs instead", r_zoom),
    Rule("title", "Document", "markup", "FIX", "pages have a <title>", "name the page, then the app: \"Invoices — Acme\" (WCAG 2.4.2)", r_title),
    Rule("third-party", "Document", "markup", "WARN", "no third-party script or stylesheet without integrity", "self-host it from the app's origin, or pin the version and add integrity= (ui-craft ground rules)", r_third_party),
    Rule("img-alt", "Content", "markup", "FIX", "every <img> has alt", "alt=\"what it shows\", or alt=\"\" when decorative (WCAG 1.1.1)", r_img_alt),
    Rule("img-size", "Content", "markup", "WARN", "every <img> has width and height", "width/height attributes or CSS aspect-ratio reserve the space (CLS)", r_img_size),
    Rule("button-name", "Names and labels", "markup", "FIX", "every button has a name", "aria-label on icon-only buttons, aria-hidden=\"true\" on the icon (WCAG 4.1.2)", r_button_name),
    Rule("link-name", "Names and labels", "markup", "FIX", "every link has a name", "link text, or aria-label on an icon link (WCAG 2.4.4)", r_link_name),
    Rule("field-label", "Names and labels", "markup", "FIX", "every form field has a label", "<label for=…> bound to the field; a placeholder is not a label (WCAG 3.3.2)", r_field_label),
    Rule("click-div", "Keyboard", "markup", "FIX", "no click handler on a non-interactive element", "use <button> (or <a href> to navigate): keyboard, focus and role come with it (WCAG 2.1.1)", r_click_div),
    Rule("tabindex-positive", "Keyboard", "markup", "FIX", "no positive tabindex", "tabindex=\"0\" or DOM order; positive values break the focus order (WCAG 2.4.3)", r_tabindex),
    Rule("paste-blocked", "Keyboard", "code", "FIX", "paste is never blocked", "let paste through: password managers and codes need it (WCAG 3.3.8)", r_paste),
    Rule("outline-none", "Focus and motion", "style", "WARN", "outlines are not removed", "replace them with a :focus-visible ring of 3:1 contrast, never bare outline: none (WCAG 2.4.7)", r_outline),
    Rule("transition-all", "Focus and motion", "style", "WARN", "no transition: all", "list the properties (transform, opacity): `all` animates layout and colours you did not mean (ui-motion skill)", r_transition_all),
    Rule("layout-animation", "Focus and motion", "style", "WARN", "animations move transform/opacity, not layout", "animate transform/opacity; width/top/margin re-run layout every frame (ui-motion skill, performance)", r_layout_animation),
    Rule("vh-100", "Mobile", "style", "WARN", "full-height layouts use dvh/svh", "100dvh (with a 100vh line before it for old browsers): 100vh hides content under the phone's toolbar (mobile-web skill §5)", r_vh),
    Rule("tiny-font", "Typography", "style", "WARN", "no text under 12px", "12px is the floor; body 16px (ui-craft skill §3)", r_tiny_font),
    Rule("font-display", "Typography", "style", "WARN", "@font-face sets font-display", "font-display: swap and a metric-matched fallback (no invisible text while the font loads)", r_font_display),
    Rule("select-none", "Typography", "style", "WARN", "text is selectable", "user-select: none only on controls, never on html/body/* (people copy IDs and errors)", r_select_none),
]


@dataclass
class Report:
    rows: list[dict] = field(default_factory=list)
    limit: int = 8

    def add(self, section: str, status: str, what: str, hint: str = "", where=(), rule: str = "") -> None:
        """rule: the --skip id of a static rule; empty for live rows."""
        self.rows.append({"section": section, "status": status, "rule": rule, "what": what,
                          "hint": hint if status in ("FIX", "WARN") else "", "where": list(where)})

    def counts(self) -> dict:
        return {k.lower(): sum(r["status"] == k for r in self.rows) for k in ("OK", "FIX", "WARN", "SKIP")}

    def text(self) -> str:
        out, section = [], None
        order = list(dict.fromkeys(r["section"] for r in self.rows))
        for row in sorted(self.rows, key=lambda r: order.index(r["section"])):   # stable: rule order kept
            if row["section"] != section:
                section = row["section"]
                out.append(f"== {section}")
            out.append(f"{row['status']:<6}{row['what']}")
            where = row["where"]
            out += [f"      at {w}" for w in where[: self.limit]]
            if len(where) > self.limit:
                out.append(f"      … {len(where) - self.limit} more (--json lists them all)")
            if row["hint"]:
                out.append(f"      -> {row['hint']}")
        c = self.counts()
        out.append(f"{c['fix']} to fix, {c['warn']} to look at, {c['ok']} OK, {c['skip']} skipped")
        return "\n".join(out)


def _in_scope(rule: Rule, src: Source) -> bool:
    if rule.scope == "markup":
        return src.markup
    if rule.scope == "style":
        return src.markup or src.suffix in STYLE
    return src.markup or src.suffix in SCRIPT


def project_facts(sources: list[Source]) -> dict:
    blob = "\n".join(s.text for s in sources if s.markup or s.suffix in STYLE)
    code = "\n".join(s.text for s in sources)
    return {
        "focus_visible": re.search(r":focus-visible|focus-visible:", blob) is not None,
        "motion": re.search(r"@keyframes|animation(?:-name)?\s*:|transition\s*:|(?<![\w-])(?:animate-|transition\b)|framer-motion|from ['\"]motion|gsap", code) is not None,
        "reduced_motion": re.search(r"prefers-reduced-motion|motion-reduce:|motion-safe:|useReducedMotion|reducedMotion", code) is not None,
        "color_scheme": re.search(r"color-scheme", blob) is not None,
        "theme_color": re.search(r"theme-color|themeColor", code) is not None,
        "hover": re.search(r":hover\b", blob) is not None,
        "hover_guard": re.search(r"\(\s*hover\s*:\s*hover\s*\)", blob) is not None,
        "documents": any(s.document for s in sources),
    }


def run_static(sources: list[Source], report: Report, skip: set[str]) -> None:
    facts = project_facts(sources)
    for rule in RULES:
        if rule.id in skip:
            continue
        scoped = [s for s in sources if _in_scope(rule, s)]
        if not scoped:
            report.add(rule.section, "SKIP", f"{rule.what} — no file to check", rule=rule.id)
            continue
        where = [f"{s.rel}:{s.line(i)}" + (f" ({d})" if d else "") for s in scoped for i, d in rule.find(s)]
        status = rule.status
        if rule.id == "outline-none" and where and not facts["focus_visible"]:
            status = "FIX"   # outlines removed and no :focus-visible anywhere: focus is invisible
        report.add(rule.section, status if where else "OK", rule.what, rule.hint, where, rule.id)
    project_rows(sources, facts, report, skip)


def project_rows(sources: list[Source], facts: dict, report: Report, skip: set[str]) -> None:
    def row(rule_id, section, failed, status, what, hint):
        if rule_id not in skip:
            report.add(section, status if failed else "OK", what, hint, rule=rule_id)

    row("reduced-motion", "Focus and motion", facts["motion"] and not facts["reduced_motion"], "FIX",
        "motion respects prefers-reduced-motion",
        "@media (prefers-reduced-motion: reduce) { … } turns large movement into a fade or nothing (ui-motion skill)")
    row("color-scheme", "Colour", not facts["color_scheme"], "WARN", "color-scheme is declared",
        ":root { color-scheme: light dark; } so form controls and scrollbars follow the theme")
    row("theme-color", "Colour", facts["documents"] and not facts["theme_color"], "WARN", "pages set theme-color",
        "<meta name=\"theme-color\" content=\"…\" media=\"(prefers-color-scheme: dark)\"> per scheme (mobile-web skill §10)")
    row("hover-guard", "Mobile", facts["hover"] and not facts["hover_guard"], "WARN", "hover styles are limited to devices that hover",
        "wrap :hover rules in @media (hover: hover) and (pointer: fine), or a tap leaves them stuck on")
    sprawl_rows(sources, report, skip)


def sprawl_rows(sources: list[Source], report: Report, skip: set[str]) -> None:
    if "token-sprawl" in skip:
        return
    styles = [s for s in sources if s.suffix in STYLE or s.markup]
    colours, sizes = set(), set()
    for s in styles:
        for line in s.text.splitlines():
            if re.match(r"\s*--[\w-]+\s*:", line):
                continue   # a token definition is the cure, not the sprawl
            for hexa in re.findall(r"#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b(?![-\w])", line):
                h = hexa.lower()
                colours.add(h if len(h) == 7 else "#" + "".join(c * 2 for c in h[1:]))
            sizes.update(re.findall(r"font-size\s*:\s*([\d.]+(?:px|rem|em))", line))
    too_many = len(colours) > 16 or len(sizes) > 8
    report.add("Colour", "WARN" if too_many else "OK",
               f"few raw values outside tokens ({len(colours)} hex colours, {len(sizes)} font sizes)",
               "collapse near-duplicates into :root role tokens (--text, --text-muted, --accent…) and a 5-6 step type scale (ui-craft skill §4, §10)",
               rule="token-sprawl")


# --- live checks --------------------------------------------------------------------------------

def _driver():
    here = Path(__file__).resolve().parent
    sys.path.insert(0, str(here.parent.parent / "headless-ui-smoke" / "scripts"))
    try:
        import cdp_smoke   # the headless-ui-smoke skill's DevTools driver, installed beside this skill
    except ImportError:
        raise SystemExit("ui_doctor: --url needs the headless-ui-smoke skill installed beside this one") from None
    return cdp_smoke, (here / "ui_audit.js").read_text(encoding="utf-8")


def _audit(browser, source: str, pass_: str, limit: int):
    expression = f"({source})({json.dumps({'pass': pass_, 'limit': limit})})"
    result = browser.call("Runtime.evaluate", {"expression": expression, "awaitPromise": True, "returnByValue": True}, timeout=60)
    if result.get("exceptionDetails"):
        detail = (result["exceptionDetails"].get("exception") or {}).get("description", "error")
        raise RuntimeError(f"in-page audit ({pass_}) failed: {detail.splitlines()[0]}")
    return (result.get("result") or {}).get("value") or {}


def _items(bucket: dict) -> list[str]:
    return [f"{i['sel']}" + (f" \"{i['text']}\"" if i["text"] else "") + (f" ({i['detail']})" if i["detail"] else "") for i in bucket.get("items", [])] + \
        ([f"… and {bucket['count'] - len(bucket['items'])} more on the page"] if bucket.get("count", 0) > len(bucket.get("items", [])) else [])


def _bucket_row(report, section, bucket, status, what, hint):
    report.add(section, status if bucket.get("count") else "OK", what + (f" — {bucket['count']} found" if bucket.get("count") else ""), hint, _items(bucket))


def live_rows(report: Report, data: dict) -> None:
    main, dark = data["main"], data["dark"]
    S = "Live page"
    report.add(S, "OK" if main.get("lang") else "FIX", "the rendered page has a lang", "<html lang=…> (WCAG 3.1.1)")
    report.add(S, "OK" if main.get("title") else "FIX", "the rendered page has a title", "set document.title per view in a single-page app (WCAG 2.4.2)")
    errors = data["errors"]
    report.add(S, "FIX" if errors else "OK", "no page errors (exceptions, console.error, failed requests)", "fix them first: the headless-ui-smoke skill reproduces each one", errors)
    _bucket_row(report, S, main["contrast"], "FIX", "text contrast in light mode", "4.5:1 for text, 3:1 from 24px (or 18.66px bold) — web-accessibility skill §7")
    light_seen = {(i["sel"], i["detail"]) for i in main["contrast"]["items"]}
    dark_only = {"count": 0, "items": [i for i in dark["items"] if (i["sel"], i["detail"]) not in light_seen]}
    dark_only["count"] = len(dark_only["items"])
    _bucket_row(report, S, dark_only, "FIX", "text contrast in dark mode (prefers-color-scheme: dark)", "dark mode is designed, not inverted: lighten muted text and borders (ui-craft skill §4)")
    _bucket_row(report, S, main["unnamed"], "FIX", "buttons and links have an accessible name", "visible text or aria-label (WCAG 4.1.2)")
    _bucket_row(report, S, main["noAlt"], "FIX", "rendered images have alt", "alt=\"…\" or alt=\"\" (WCAG 1.1.1)")
    _bucket_row(report, S, main["unlabelled"], "FIX", "rendered form fields have a label", "<label for> or aria-label (WCAG 3.3.2)")
    _bucket_row(report, S, main["smallTargets"], "WARN", "pointer targets are at least 24×24px", "pad the control or extend its hit area; 44×44 on touch (WCAG 2.5.8)")
    headings = main["headings"]
    report.add(S, "OK" if headings["h1"] == 1 else "WARN", f"one <h1> on the page (found {headings['h1']})", "one h1 naming the page; the rest step down")
    _bucket_row(report, S, headings["skipped"], "WARN", "heading levels do not skip", "h2 after h1, h3 after h2 — screen-reader users navigate by them")
    _bucket_row(report, S, main["devWords"], "FIX", "no undefined / NaN / [object Object] on screen", "a missing value needs a designed state (ui-craft skill §5)")
    _bucket_row(report, S, main["dots"], "WARN", "real ellipsis (…) in visible text", "\"Loading…\", not \"Loading...\" (ui-craft skill §3)")
    vitals_rows(report, main.get("vitals") or {})
    phone_rows(report, data)


def vitals_rows(report: Report, vitals: dict) -> None:
    cls, lcp = vitals.get("cls"), vitals.get("lcp")
    if cls is None:
        report.add("Live page", "SKIP", "layout shift (CLS) — the browser did not report it")
    else:
        report.add("Live page", "FIX" if cls > 0.1 else "OK", f"layout shift while loading (CLS {cls:.3f}, good ≤ 0.1)",
                   "reserve space: width/height or aspect-ratio on media, min-height on late content")
    if lcp is not None:
        report.add("Live page", "WARN" if lcp > 2500 else "OK", f"largest paint (lab LCP {lcp / 1000:.2f}s, good ≤ 2.5s)",
                   "lab number on this machine; field data (CrUX, RUM) is what counts — make the LCP image discoverable, fetchpriority=\"high\", never lazy")


def phone_rows(report: Report, data: dict) -> None:
    phone, motion, focus = data["phone"], data["motion"], data["focus"]
    S = "Live page"
    _bucket_row(report, S, phone["overflow"], "FIX", f"no sideways scroll at {phone.get('width', 320)}px wide", "min-width: 0 on flex/grid children, max-width: 100% on media, wrap long words (WCAG 1.4.10)")
    _bucket_row(report, S, phone["smallInputs"], "WARN", "inputs are 16px+ on phones (no iOS zoom on focus)", "font-size: max(16px, 1rem) on inputs under @media (pointer: coarse) (mobile-web skill §4)")
    _bucket_row(report, S, motion, "WARN", "nothing loops forever under prefers-reduced-motion", "stop or drop infinite animations in @media (prefers-reduced-motion: reduce)")
    _bucket_row(report, S, focus, "WARN", "focus is visible on every control", "a :focus-visible ring with 3:1 contrast; tab through the page to confirm (WCAG 2.4.7)")


def run_live(args, report: Report) -> int:
    cdp, source = _driver()
    profile = Path(tempfile.mkdtemp(prefix="ui-doctor-profile-"))
    try:
        browser = cdp.Browser(cdp.find_chrome(args.chrome), profile, (1400, 900), 1, args.no_sandbox)
    except (OSError, RuntimeError, SystemExit) as exc:
        print(f"ui_doctor: could not drive Chrome: {exc}", file=sys.stderr)
        shutil.rmtree(profile, ignore_errors=True)
        return 2
    try:
        data = drive(browser, source, args)
    except (RuntimeError, TimeoutError) as exc:
        report.add("Live page", "FIX", f"could not audit {args.url}", str(exc))
        return 0
    finally:
        browser.close()
        shutil.rmtree(profile, ignore_errors=True)
    ignored = [re.compile(p) for p in args.ignore]
    data["errors"] = [e for e in dict.fromkeys(browser.errors) if not any(p.search(e) for p in ignored)]
    live_rows(report, data)
    return 0


def drive(browser, source: str, args) -> dict:
    def media(*features):
        browser.call("Emulation.setEmulatedMedia", {"features": [{"name": n, "value": v} for n, v in features]})
        browser.settle(0.4)

    def shot(name):
        if args.shots:
            browser.screenshot(args.shots / name, False)

    browser.call("Page.navigate", {"url": args.url})
    browser.settle(args.settle)
    if args.wait_for and not browser.wait_for(args.wait_for, args.timeout):
        raise RuntimeError(f"never became true within {args.timeout:g}s: {args.wait_for}")
    data = {"main": _audit(browser, source, "main", args.limit)}
    shot("desktop.png")
    media(("prefers-color-scheme", "dark"))
    data["dark"] = _audit(browser, source, "contrast", args.limit)
    shot("desktop-dark.png")
    media(("prefers-reduced-motion", "reduce"))
    data["motion"] = _audit(browser, source, "motion", args.limit)
    media()
    browser.call("Emulation.setDeviceMetricsOverride", {"width": 320, "height": 720, "deviceScaleFactor": 2, "mobile": True})
    browser.settle(0.6)
    data["phone"] = _audit(browser, source, "phone", args.limit)
    shot("phone-320.png")
    browser.call("Emulation.setDeviceMetricsOverride", {"width": 1400, "height": 900, "deviceScaleFactor": 1, "mobile": False})
    browser.call("Emulation.setFocusEmulationEnabled", {"enabled": True})   # a headless page never has focus
    browser.settle(0.3)
    data["focus"] = _audit(browser, source, "focus", args.limit)
    return data


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__.split("\n\n", 1)[1])
    parser.add_argument("path", nargs="?", default=".", type=Path, help="project folder to scan (default .)")
    parser.add_argument("--url", help="also audit this page in headless Chrome (a throwaway instance on 127.0.0.1, never live user data)")
    parser.add_argument("--no-static", action="store_true", help="skip the source scan (with --url)")
    parser.add_argument("--wait-for", metavar="JS", help="JavaScript condition that means 'rendered' (as in headless-ui-smoke)")
    parser.add_argument("--settle", type=float, default=1.5, help="seconds to let the page run after it loads (default 1.5)")
    parser.add_argument("--timeout", type=float, default=20, help="seconds --wait-for may take (default 20)")
    parser.add_argument("--shots", type=Path, metavar="DIR", help="save desktop, dark and 320px screenshots here")
    parser.add_argument("--ignore", action="append", default=[], metavar="REGEX", help="page errors to ignore (repeatable)")
    parser.add_argument("--skip", action="append", default=[], metavar="RULE", help="rule id to leave out, e.g. vh-100 (repeatable)")
    parser.add_argument("--limit", type=int, default=8, help="places listed per rule in the text report (default 8)")
    parser.add_argument("--json", action="store_true", help="one JSON document on stdout instead of the text report")
    parser.add_argument("--chrome", help="browser binary (default: search, or $CHROME_PATH)")
    parser.add_argument("--no-sandbox", action="store_true", help="needed in containers / CI running as root")
    args = parser.parse_args(argv)
    if args.no_static and not args.url:
        parser.error("--no-static needs --url")
    if not args.no_static and not args.path.is_dir():
        parser.error(f"not a folder: {args.path}")
    return args


def main(argv=None) -> int:
    with contextlib.suppress(AttributeError, OSError):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = parse_args(argv)
    report = Report(limit=args.limit)
    if not args.no_static:
        sources = collect(args.path.resolve())
        if not any(s.markup or s.suffix in STYLE for s in sources):
            report.add("Static", "SKIP", f"no HTML, component or CSS file under {args.path}")
        else:
            run_static(sources, report, set(args.skip))
    if args.url and run_live(args, report) == 2:
        return 2
    counts = report.counts()
    if args.json:
        print(json.dumps({"schema": 1, "path": None if args.no_static else str(args.path.resolve()), "url": args.url,
                          "ok": counts["fix"] == 0, "counts": counts, "checks": report.rows}, ensure_ascii=False, indent=1))
    else:
        print(report.text())
    return 0 if counts["fix"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
