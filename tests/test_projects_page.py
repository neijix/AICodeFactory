"""The projects page: status from doctor's records, skill use from transcripts, a safe page."""

from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

from engine.projects_page import collect
from engine.projects_page.cli import main, parse_args
from engine.projects_page.collect import build_projects, build_skills, classify, skills_off, summary
from engine.projects_page.render import render_html, render_text
from engine.projects_page.usage import ProjectResolver, config_dirs, scan, skills_in_line

BRAIN = Path(__file__).resolve().parent.parent


def _record(name: str, **extra) -> dict:
    base = {"name": name, "path": f"/root/{name}", "bootstrapped": True, "ai_files": "current",
            "plan": "ok", "remote": True, "dirty": False, "unpushed": 0,
            "placeholder_docs": [], "missing_headings": []}
    base.update(extra)
    return base


def _skill_call(cwd: str, skill: str, call_id: str, when: str = "2026-10-01T10:00:00Z") -> dict:
    return {"type": "assistant", "cwd": cwd, "timestamp": when, "uuid": "u-" + call_id,
            "message": {"content": [{"type": "tool_use", "id": call_id, "name": "Skill",
                                     "input": {"skill": skill}}]}}


class ClassifyTests(unittest.TestCase):
    def test_each_status_and_its_next_step(self) -> None:
        self.assertEqual(classify(_record("a", bootstrapped=False))[0], "missing")
        self.assertIn("aicf update a", classify(_record("a", bootstrapped=False))[1])
        self.assertEqual(classify(_record("a", placeholder_docs=["AGENTS.md"]))[0], "unfinished")
        self.assertEqual(classify(_record("a", missing_headings=["## Taste"]))[0], "unfinished")
        self.assertEqual(classify(_record("a", ai_files="stale")), ("stale", "aicf update a"))
        self.assertEqual(classify(_record("a", plan="off-plan"))[0], "off-plan")
        self.assertEqual(classify(_record("a")), ("ok", ""))

    def test_need_work_sorts_first(self) -> None:
        rows = build_projects({"projects": [_record("b"), _record("a", bootstrapped=False)]}, {})
        self.assertEqual([r["name"] for r in rows], ["a", "b"])
        self.assertEqual(summary(rows)["missing"], 1)
        self.assertEqual(summary(rows)["total"], 2)

    def test_broken_doctor_output_is_one_error(self) -> None:
        with self.assertRaises(collect.DoctorError):
            collect.parse_doctor("not json")
        with self.assertRaises(collect.DoctorError):
            collect.parse_doctor('{"schema": 1}')


class UsageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="projects-page-"))
        self.root = self.tmp / "code"
        (self.root / "alpha").mkdir(parents=True)
        (self.root / "beta").mkdir()
        self.claude = self.tmp / "home" / ".claude"
        self.sessions = self.claude / "projects" / "slug"
        self.sessions.mkdir(parents=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, name: str, entries: list[dict]) -> None:
        with (self.sessions / name).open("w", encoding="utf-8") as fh:
            for entry in entries:
                fh.write(json.dumps(entry) + "\n")

    def test_skill_calls_and_slash_prompts_counted_once(self) -> None:
        alpha = str(self.root / "alpha" / "src")
        slash = {"type": "user", "cwd": str(self.root / "beta"), "uuid": "s1",
                 "timestamp": "2026-10-03T00:00:00Z",
                 "message": {"content": "<command-name>/bootstrap-ai</command-name>"}}
        builtin = dict(slash, uuid="s2", message={"content": "<command-name>/model</command-name>"})
        # api-request lines replay the history: never a use.
        replay = {"type": "api-request", "cwd": alpha, "message": _skill_call(alpha, "x", "c9")["message"]}
        self._write("one.jsonl", [_skill_call(alpha, "code-health", "c1"), slash, builtin, replay,
                                  _skill_call("/elsewhere", "code-health", "c2")])
        # A resumed session copies earlier lines: the same tool call id is one use.
        self._write("two.jsonl", [_skill_call(alpha, "code-health", "c1"),
                                  _skill_call(alpha, "code-health", "c3", "2026-10-05T00:00:00Z")])
        alpha_dir, beta_dir = str(self.root / "alpha"), str(self.root / "beta")
        usage, orphans = scan([self.claude], ProjectResolver([alpha_dir, beta_dir]),
                              {"code-health", "bootstrap-ai"})
        self.assertEqual(usage[alpha_dir]["code-health"], {"count": 2, "last": "2026-10-05T00:00:00Z"})
        self.assertEqual(usage[beta_dir]["bootstrap-ai"]["count"], 1)
        self.assertNotIn("model", usage.get(beta_dir, {}))
        self.assertEqual(orphans, 1)

    def test_unknown_slash_command_is_not_a_skill(self) -> None:
        entry = {"type": "user", "uuid": "u", "message": {"content": "<command-name>/clear</command-name>"}}
        self.assertEqual(skills_in_line(entry, {"bootstrap-ai"}), [])

    def test_worktree_outside_the_root_maps_to_its_project(self) -> None:
        repo = self.root / "alpha"
        env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@e",
                   GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@e")
        for args in (["init", "-q"], ["commit", "-q", "--allow-empty", "-m", "x"],
                     ["worktree", "add", "-q", str(self.tmp / "wt")]):
            subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, env=env)
        resolve = ProjectResolver([str(repo), str(self.root / "beta")])
        self.assertEqual(os.path.normcase(os.path.realpath(resolve(str(self.tmp / "wt")))),
                         os.path.normcase(os.path.realpath(str(repo))))
        self.assertIsNone(resolve(str(self.tmp / "gone")))

    def test_projects_of_every_code_root_are_resolved(self) -> None:
        work = self.tmp / "work" / "gamma"
        work.mkdir(parents=True)
        resolve = ProjectResolver([str(self.root / "alpha"), str(work)])
        self.assertEqual(resolve(str(work / "src")), str(work))
        self.assertEqual(resolve(str(self.root / "alpha")), str(self.root / "alpha"))
        self.assertIsNone(resolve(str(self.root / "beta")))

    def test_profiles_add_their_config_dirs(self) -> None:
        home = self.tmp / "home"
        (home / ".claude-work").mkdir()
        (home / ".claude-profiles").write_text(f"{self.tmp}/work\t~/.claude-work\n", encoding="utf-8")
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": ""}):
            self.assertEqual(config_dirs(home), [home / ".claude", home / ".claude-work"])


class SkillsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="projects-page-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_skills_off_reads_skill_overrides(self) -> None:
        (self.tmp / ".claude").mkdir()
        (self.tmp / ".claude" / "settings.local.json").write_text(
            '{"skillOverrides": {"a": "off", "b": "on"}}', encoding="utf-8")
        self.assertEqual(skills_off(self.tmp), ["a"])
        self.assertEqual(skills_off(self.tmp / "none"), [])

    def test_catalog_brain_wins_over_overlay(self) -> None:
        brain, overlay = self.tmp / "brain", self.tmp / "overlay"
        for folder, name in ((brain, "shared"), (brain, "mine"), (overlay, "shared"), (overlay, "extra")):
            (folder / "skills" / name).mkdir(parents=True)
            (folder / "skills" / name / "SKILL.md").write_text("x", encoding="utf-8")
        with mock.patch.object(collect, "overlay_dir", return_value=overlay), \
                mock.patch.object(collect, "overlay_skill_dirs", return_value=[]):
            catalog = collect.skill_catalog(brain)
        self.assertEqual(catalog, {"extra": "overlay", "mine": "brain", "shared": "brain"})

    def test_skill_rows_list_users_and_unused(self) -> None:
        projects = build_projects({"projects": [_record("a"), _record("b")]},
                                  {"/root/a": {"x": {"count": 3, "last": "2026-10-02"}},
                                   "/root/b": {"x": {"count": 1, "last": "2026-10-04"}}})
        rows = build_skills({"x": "brain", "y": "brain"}, projects)
        self.assertEqual(rows[0], {"name": "x", "source": "brain", "drives": "", "uses": 4,
                                   "last": "2026-10-04", "projects": {"a": 3, "b": 1}, "off_in": []})
        self.assertEqual(rows[1]["uses"], 0)

    def test_a_skill_names_the_project_it_drives(self) -> None:
        brain, overlay = self.tmp / "brain", self.tmp / "overlay"
        skills = {(overlay, "tool-cli"): "---\nname: tool-cli\nmetadata:\n  project: \"Tool\"\n---\n",
                  (overlay, "plain"): "---\nname: plain\nproject: Tool\n---\n",
                  (brain, "base"): "---\nname: base\n---\n"}
        for (folder, name), text in skills.items():
            (folder / "skills" / name).mkdir(parents=True)
            (folder / "skills" / name / "SKILL.md").write_text(text, encoding="utf-8")
        with mock.patch.object(collect, "overlay_dir", return_value=overlay), \
                mock.patch.object(collect, "overlay_skill_dirs", return_value=[]):
            drives = collect.skill_projects(brain)
        self.assertEqual(drives, {"tool-cli": "Tool"})
        projects = build_projects({"projects": [_record("tool"), _record("other")]}, {}, drives)
        self.assertEqual({p["name"]: p["agent_skills"] for p in projects}, {"tool": ["tool-cli"], "other": []})
        self.assertEqual(build_skills({"tool-cli": "overlay"}, projects, drives)[0]["drives"], "Tool")


class PageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="projects-page-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _data(self, name: str) -> dict:
        projects = build_projects({"projects": [_record(name, bootstrapped=False)]},
                                  {name: {"<img>": {"count": 1, "last": ""}}})
        return {"code_root": "/root", "generated": "now", "summary": summary(projects),
                "projects": projects, "skills": build_skills({}, projects), "usage_note": "n"}

    def test_every_value_is_escaped(self) -> None:
        page = render_html(self._data("<script>alert(1)</script>"))
        self.assertNotIn("<script>alert", page)
        self.assertNotIn("<img>", page)
        self.assertIn("&lt;script&gt;", page)
        self.assertIn("default-src 'none'", page)

    def test_text_summary_names_the_next_step(self) -> None:
        text = render_text(self._data("alpha"))
        self.assertIn("Not bootstrapped", text)
        self.assertIn("next: aicf update alpha", text)

    def test_cli_writes_the_page_from_a_saved_doctor_document(self) -> None:
        saved = self.tmp / "doctor.json"
        saved.write_text(json.dumps({"schema": 1, "code_root": str(self.tmp),
                                     "projects": [_record("alpha", path=str(self.tmp / "alpha"))]}),
                         encoding="utf-8")
        out = self.tmp / "page" / "projects.html"
        with redirect_stdout(io.StringIO()) as buf:
            code = main(["--doctor-json", str(saved), "--out", str(out), "--no-usage"], BRAIN)
        self.assertEqual(code, 0)
        self.assertIn("alpha", out.read_text(encoding="utf-8"))
        self.assertIn(f"Page: {out}", buf.getvalue())
        with redirect_stdout(io.StringIO()) as buf:
            self.assertEqual(main(["--doctor-json", str(saved), "--json", "--no-usage"], BRAIN), 0)
        self.assertEqual(json.loads(buf.getvalue())["summary"]["ok"], 1)

    def test_bad_option_exits_2(self) -> None:
        with self.assertRaises(ValueError):
            parse_args(["--out"])
        with redirect_stdout(io.StringIO()), mock.patch("sys.stderr", io.StringIO()):
            self.assertEqual(main(["--nope"], BRAIN), 2)


if __name__ == "__main__":
    unittest.main()
