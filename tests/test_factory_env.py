"""Factory config: layers, the generated project files, the skill stamp, a JSON key merge."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import unittest
from pathlib import Path

from engine.factory_env.apply import apply_project
from engine.factory_env.cli import main, set_layer
from engine.factory_env.merge import MARKER, merge_values, recover
from engine.factory_env.paths import default_label, is_work_path
from engine.factory_env.resolve import at_root
from engine.factory_env.schema import ConfigError, validate_document
from engine.factory_env.skills import (
    _source_folders, skill_keep, skill_stamp, skills_begin, skills_current, skills_finish, tree_hash,
)
from engine.factory_env.textio import write_lf


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True)


class FactoryEnvTests(unittest.TestCase):
    def setUp(self) -> None:
        self._home = os.environ.get("HOME")
        self._overlay = os.environ.get("AI_TEMPLATE_OVERLAY_DIR")
        self._work_roots = os.environ.get("AI_WORK_ROOTS")
        # Run from a Claude Code shell or not, apply must see neither.
        self._claude = {name: os.environ.pop(name, None) for name in ("CLAUDECODE", "CLAUDE_PROJECT_DIR")}
        self.tmp = Path(self.id().replace(".", "_"))
        # A real temp dir, not a name under the repo.
        import tempfile
        self.tmp = Path(tempfile.mkdtemp(prefix="factory-env-"))
        os.environ["HOME"] = str(self.tmp / "home")
        (self.tmp / "home").mkdir()
        os.environ["AI_TEMPLATE_OVERLAY_DIR"] = "none"
        # The machine's ~/.ai-work-roots is never read: HOME is a temp dir and the list is empty.
        os.environ["AI_WORK_ROOTS"] = "none"

    def tearDown(self) -> None:
        if self._home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = self._home
        if self._overlay is None:
            os.environ.pop("AI_TEMPLATE_OVERLAY_DIR", None)
        else:
            os.environ["AI_TEMPLATE_OVERLAY_DIR"] = self._overlay
        os.environ.pop("AI_WORK_ROOTS", None)
        if self._work_roots is not None:
            os.environ["AI_WORK_ROOTS"] = self._work_roots
        for name, value in self._claude.items():
            os.environ.pop(name, None)
            if value is not None:
                os.environ[name] = value
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _root(self, name: str = "Code") -> tuple[Path, Path]:
        root = self.tmp / name
        (root / ".ai-root").mkdir(parents=True)
        project = root / "demo"
        project.mkdir()
        _git(project, "init", "-q")
        return root, project

    def test_no_config_writes_nothing(self) -> None:
        _root, project = self._root()
        self.assertEqual(apply_project(project, dry_run=False), 0)
        self.assertFalse((project / "CLAUDE.local.md").exists())
        self.assertFalse((project / ".claude" / "settings.local.json").exists())

    def test_environment_turns_a_brain_skill_off_and_keeps_other_settings(self) -> None:
        root, project = self._root()
        (root / ".ai-root" / "environment.json").write_text(
            json.dumps({"label": "home", "skills.off": ["bootstrap-ai"]}),
            encoding="utf-8",
        )
        settings = project / ".claude" / "settings.local.json"
        settings.parent.mkdir()
        settings.write_text(json.dumps({"autoMemoryDirectory": "/mem"}) + "\n", encoding="utf-8")
        apply_project(project, dry_run=False)
        data = json.loads(settings.read_text(encoding="utf-8"))
        self.assertEqual(data["autoMemoryDirectory"], "/mem")
        self.assertEqual(data["skillOverrides"]["bootstrap-ai"], "off")
        text = (project / "CLAUDE.local.md").read_text(encoding="utf-8")
        self.assertIn("bootstrap-ai", text)
        self.assertIn("configured for Claude", text)
        before = settings.read_text(encoding="utf-8")
        apply_project(project, dry_run=False)
        self.assertEqual(settings.read_text(encoding="utf-8"), before)

    def test_malformed_settings_are_left_untouched(self) -> None:
        root, project = self._root()
        (root / ".ai-root" / "environment.json").write_text(
            json.dumps({"skills.off": ["bootstrap-ai"]}), encoding="utf-8",
        )
        settings = project / ".claude" / "settings.local.json"
        settings.parent.mkdir()
        settings.write_text("{ broken", encoding="utf-8")
        apply_project(project, dry_run=False)
        self.assertEqual(settings.read_text(encoding="utf-8"), "{ broken")

    def test_work_clamps_mlx_and_personal_skills_default_off(self) -> None:
        root, _project = self._root("WorkCode")
        overlay = self.tmp / "overlay"
        skill = overlay / "skills" / "mine"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("---\nname: mine\n---\n", encoding="utf-8")
        os.environ["AI_TEMPLATE_OVERLAY_DIR"] = str(overlay)
        (root / ".ai-root" / "environment.json").write_text(
            json.dumps({"label": "work"}), encoding="utf-8",
        )
        resolved = at_root(root)
        self.assertTrue(resolved.work)
        self.assertEqual(resolved.workflow["review-prefilter"].agent, "none")
        self.assertEqual(resolved.workflow["offload"].agent, "none")
        mine = next(item for item in resolved.skills if item.name == "mine")
        self.assertEqual(mine.source, "personal")
        self.assertFalse(mine.enabled)
        brain = next(item for item in resolved.skills if item.name == "bootstrap-ai")
        self.assertTrue(brain.enabled)

    def test_a_folder_name_entry_marks_any_root_of_that_name_work(self) -> None:
        os.environ["AI_WORK_ROOTS"] = os.pathsep.join(["", "workcode"])  # case-insensitive, blanks skipped
        root, _project = self._root("WorkCode")
        resolved = at_root(root)
        self.assertEqual((resolved.work, resolved.label), (True, "work"))
        self.assertTrue(is_work_path(self.tmp / "WorkCode" / "demo" / "src"))
        self.assertFalse(is_work_path(self.tmp / "WorkCodeOld"))  # a whole component, not a substring
        personal, _ = self._root("Code")
        self.assertEqual((at_root(personal).work, at_root(personal).label), (False, "personal"))

    def test_an_absolute_entry_matches_as_a_whole_component_prefix(self) -> None:
        base = self.tmp / "jobs"
        os.environ["AI_WORK_ROOTS"] = str(base).upper() + os.sep
        self.assertTrue(is_work_path(base))
        self.assertTrue(is_work_path(base / "repo" / "src"))
        self.assertFalse(is_work_path(self.tmp / "jobsite"))
        self.assertFalse(is_work_path(self.tmp / "elsewhere" / "jobs"))  # a path entry is not a folder name

    def test_the_work_roots_file_is_read_unless_the_variable_disables_it(self) -> None:
        (self.tmp / "home" / ".ai-work-roots").write_text("# work roots\n\n  WorkCode  \n", encoding="utf-8")
        path = self.tmp / "WorkCode" / "demo"
        os.environ.pop("AI_WORK_ROOTS")
        self.assertEqual(default_label(path), "work")
        for disabled in ("none", "", "  "):
            os.environ["AI_WORK_ROOTS"] = disabled
            self.assertEqual(default_label(path), "personal")
        os.environ["AI_WORK_ROOTS"] = "Other"  # the variable replaces the file
        self.assertEqual(default_label(path), "personal")

    def test_an_environment_labelled_work_marks_its_root_work(self) -> None:
        root, project = self._root("Plain")
        self.assertFalse(is_work_path(project))
        env = root / ".ai-root" / "environment.json"
        env.write_text(json.dumps({"label": "Work"}), encoding="utf-8")
        self.assertTrue(is_work_path(project / "src"))
        self.assertTrue(at_root(root).work)
        env.write_text(json.dumps({"label": "office"}), encoding="utf-8")
        self.assertFalse(is_work_path(project / "src"))
        self.assertEqual((at_root(root).work, at_root(root).label), (False, "office"))

    def test_a_legacy_kind_folds_into_the_label(self) -> None:
        root, project = self._root("Plain")
        env = root / ".ai-root" / "environment.json"
        env.write_text(json.dumps({"kind": "work", "label": "office"}), encoding="utf-8")
        self.assertTrue(is_work_path(project))   # a work root never turns personal
        self.assertEqual((at_root(root).work, at_root(root).label), (True, "work"))
        env.write_text(json.dumps({"kind": "personal"}), encoding="utf-8")
        self.assertEqual((at_root(root).work, at_root(root).label), (False, "personal"))
        set_layer({"layer": "environment", "root": str(root), "values": {"skills.off": ["bootstrap-ai"]}})
        self.assertEqual(json.loads(env.read_text(encoding="utf-8")), {"label": "personal", "skills.off": ["bootstrap-ai"]})

    def test_an_overlay_named_dash_work_is_a_work_skill_source(self) -> None:
        root, _project = self._root()
        for name, source in (("factory-work", "work"), ("factory-private", "personal")):
            overlay = self.tmp / name
            skill = overlay / "skills" / f"{name}-skill"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(f"---\nname: {name}-skill\n---\n", encoding="utf-8")
            os.environ["AI_TEMPLATE_OVERLAY_DIR"] = str(overlay)
            item = next(entry for entry in at_root(root).skills if entry.name == f"{name}-skill")
            self.assertEqual(item.source, source)
            self.assertEqual(item.enabled, source == "personal")  # the root is personal

    def test_project_skill_stays_off_until_the_environment_turns_it_on(self) -> None:
        root, project = self._root()
        exported = root / "helper" / "skill" / "helper-skill"
        exported.mkdir(parents=True)
        (exported / "SKILL.md").write_text("---\nname: helper-skill\n---\n", encoding="utf-8")
        (root / ".ai-root" / "environment.json").write_text("{}", encoding="utf-8")
        resolved = at_root(root)
        item = next(skill for skill in resolved.skills if skill.name == "helper-skill")
        self.assertEqual(item.source, "project")
        self.assertFalse(item.enabled)
        (root / ".ai-root" / "environment.json").write_text(
            json.dumps({"skills.on": ["helper-skill"]}), encoding="utf-8",
        )
        self.assertTrue(next(skill for skill in at_root(root).skills if skill.name == "helper-skill").enabled)

    def test_work_rejects_mlx_on_set(self) -> None:
        with self.assertRaises(ConfigError):
            validate_document({"label": "work", "workflow.review.agent": "mlx"})
        with self.assertRaises(ConfigError):
            validate_document({"kind": "personal"})   # kind is gone: the label says work

    def test_stamp_skips_a_finished_install_and_reports_a_killed_one(self) -> None:
        self.assertEqual(skills_current(), 1)
        skills_begin()
        self.assertEqual(skills_current(), 1)
        skills_finish()
        self.assertEqual(skills_current(), 0)
        skills_begin()
        self.assertIn("did not finish", self._capture_current())

    def _capture_current(self) -> str:
        import io
        from contextlib import redirect_stdout
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            skills_current()
        return buffer.getvalue()

    def test_skill_roots_named_on_the_command_line_are_checked(self) -> None:
        skills_finish()
        root = self.tmp / "installed"
        root.mkdir()
        self.assertEqual(skills_current([str(root)]), 1)
        self.assertEqual(skills_current(), 0)

    def test_an_edited_copy_is_kept_and_a_pristine_one_is_replaced(self) -> None:
        source = self.tmp / "src"
        source.mkdir()
        (source / "SKILL.md").write_text("one\n", encoding="utf-8")
        dest = self.tmp / "dest"
        dest.mkdir()
        (dest / "SKILL.md").write_text("one\n", encoding="utf-8")
        self.assertEqual(skill_keep(dest, source), 1)  # no hash yet
        skill_stamp(dest, source)
        self.assertEqual(skill_keep(dest, source), 1)
        (dest / "SKILL.md").write_text("edited\n", encoding="utf-8")
        self.assertNotEqual(tree_hash(dest), tree_hash(source))
        self.assertEqual(skill_keep(dest, source), 0)

    def test_key_merge_takes_each_side_change_and_reports_a_clash(self) -> None:
        base = {"a": 1, "b": 2, "gone": 0}
        merged, clashes = merge_values(base, {"a": 1, "b": 3, "c": 4, "gone": 0}, {"a": 5, "b": 2})
        self.assertEqual(merged, {"a": 5, "b": 3, "c": 4})  # "gone" deleted locally stays deleted
        self.assertEqual(clashes, {})
        _merged, clashes = merge_values(base, {"a": 1, "b": 3}, {"a": 1, "b": 4})
        self.assertEqual(clashes, {"b": {"base": 2, "remote": 3, "local": 4}})

    def _diverged(self, remote: dict, local: dict) -> Path:
        """A repo whose `main` (local) no longer rebases cleanly onto `remote`."""
        repo = self.tmp / "hidden"
        repo.mkdir()
        _git(repo, "init", "-q")
        for key, value in (("user.name", "t"), ("user.email", "t@example.invalid"),
                           ("commit.gpgsign", "false"), ("core.autocrlf", "false")):
            _git(repo, "config", key, value)
        config = repo / "config.local" / "x.json"
        config.parent.mkdir()

        def commit(data: dict, message: str) -> None:
            write_lf(config, json.dumps(data, indent=2) + "\n")
            _git(repo, "add", "-A")
            _git(repo, "commit", "-q", "-m", message)

        commit({"a": 1, "b": 2}, "base")
        _git(repo, "branch", "-M", "main")
        _git(repo, "checkout", "-q", "-b", "remote")
        commit(remote, "remote")
        _git(repo, "checkout", "-q", "main")
        commit(local, "local")
        rebase = subprocess.run(["git", "-C", str(repo), "rebase", "-q", "remote"], capture_output=True, check=False)
        self.assertNotEqual(rebase.returncode, 0)  # adjacent lines: git alone cannot
        return repo

    def test_a_rebase_conflicting_on_different_keys_is_finished(self) -> None:
        repo = self._diverged({"a": 1, "b": 3}, {"a": 5, "b": 2})
        self.assertEqual(recover(repo / ".git", repo, "remote"), 0)
        data = json.loads((repo / "config.local" / "x.json").read_text(encoding="utf-8"))
        self.assertEqual(data, {"a": 5, "b": 3})
        self.assertFalse((repo / ".git" / "rebase-merge").exists())
        self.assertFalse((repo / ".git" / MARKER).exists())

    def test_a_clash_aborts_the_rebase_and_is_recorded(self) -> None:
        repo = self._diverged({"a": 1, "b": 3}, {"a": 1, "b": 4})
        self.assertEqual(recover(repo / ".git", repo, "remote"), 1)
        self.assertFalse((repo / ".git" / "rebase-merge").exists())
        marker = json.loads((repo / ".git" / MARKER).read_text(encoding="utf-8"))
        self.assertEqual(list(marker["clashes"]["config.local/x.json"]), ["b"])
        self.assertEqual(marker["ref"], "remote")
        head = subprocess.run(["git", "-C", str(repo), "log", "-1", "--format=%s"], capture_output=True, text=True, check=True)
        self.assertEqual(head.stdout.strip(), "local")

    def test_user_overrides_are_kept_and_ours_taken_back(self) -> None:
        root, project = self._root()
        env = root / ".ai-root" / "environment.json"
        env.write_text(json.dumps({"skills.off": ["bootstrap-ai"]}), encoding="utf-8")
        settings = project / ".claude" / "settings.local.json"
        settings.parent.mkdir()
        mine = {"mine": "on", "review-sweep": "off"}
        settings.write_text(json.dumps({"skillOverrides": mine}), encoding="utf-8")
        apply_project(project, dry_run=False)
        self.assertEqual(json.loads(settings.read_text(encoding="utf-8"))["skillOverrides"], {**mine, "bootstrap-ai": "off"})
        env.write_text("{}", encoding="utf-8")
        apply_project(project, dry_run=False)
        self.assertEqual(json.loads(settings.read_text(encoding="utf-8"))["skillOverrides"], mine)
        env.unlink()
        apply_project(project, dry_run=False)
        self.assertFalse((project / "CLAUDE.local.md").exists())  # it held our section only

    def test_a_second_run_under_claude_code_is_silent(self) -> None:
        root, project = self._root()
        (root / ".ai-root" / "environment.json").write_text(json.dumps({"skills.off": ["bootstrap-ai"]}), encoding="utf-8")
        os.environ["CLAUDECODE"] = "1"
        self.assertIn("never use them", self._capture(lambda: apply_project(project, dry_run=False)))
        self.assertEqual(self._capture(lambda: apply_project(project, dry_run=False)), "")
        os.environ.pop("CLAUDECODE")
        self.assertIn("never use them", self._capture(lambda: apply_project(project, dry_run=False)))

    def test_a_tracked_settings_file_is_not_written(self) -> None:
        root, project = self._root()
        (root / ".ai-root" / "environment.json").write_text(json.dumps({"skills.off": ["bootstrap-ai"]}), encoding="utf-8")
        settings = project / ".claude" / "settings.local.json"
        settings.parent.mkdir()
        settings.write_text("{}\n", encoding="utf-8")
        _git(project, "add", "-f", ".claude/settings.local.json")
        apply_project(project, dry_run=False)
        self.assertEqual(settings.read_text(encoding="utf-8"), "{}\n")
        self.assertIn("bootstrap-ai", (project / "CLAUDE.local.md").read_text(encoding="utf-8"))

    def test_a_recorded_conflict_says_what_and_how(self) -> None:
        _root, project = self._root()
        hidden = project / ".git" / "ai-context"
        hidden.mkdir()
        (hidden / MARKER).write_text(json.dumps({"clashes": {"config.local/x.json": {"b": {}}}, "other": [], "ref": "refs/x"}), encoding="utf-8")
        out = self._capture(lambda: apply_project(project, dry_run=False))
        self.assertIn("config.local/x.json (b)", out)
        self.assertIn("rebase refs/x", out)
        self.assertFalse((project / "CLAUDE.local.md").exists())  # a conflict alone publishes nothing

    def test_the_overlay_named_by_the_marker_file_is_a_skill_source(self) -> None:
        overlay = self.tmp / "overlay"
        (overlay / "skills").mkdir(parents=True)
        (self.tmp / "home" / ".ai-template-overlay-dir").write_text(str(overlay) + "\n", encoding="utf-8")
        os.environ.pop("AI_TEMPLATE_OVERLAY_DIR")
        self.assertIn((overlay / "skills").resolve(), [path.resolve() for path in _source_folders()])

    def test_an_overlay_in_the_old_layout_is_still_a_skill_source(self) -> None:
        root, _project = self._root()
        overlay = self.tmp / "overlay"
        skill = overlay / "vscode-global" / "skills" / "old-mine"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("---\nname: old-mine\n---\n", encoding="utf-8")
        os.environ["AI_TEMPLATE_OVERLAY_DIR"] = str(overlay)
        self.assertIn((overlay / "vscode-global" / "skills").resolve(), [path.resolve() for path in _source_folders()])
        self.assertIn("old-mine", [item.name for item in at_root(root).skills])

    def test_pycache_is_not_an_edit_and_a_stale_pristine_copy_is_replaced(self) -> None:
        source = self.tmp / "src"
        source.mkdir()
        (source / "SKILL.md").write_text("one\n", encoding="utf-8")
        dest = self.tmp / "dest"
        dest.mkdir()
        (dest / "SKILL.md").write_text("one\n", encoding="utf-8")
        skill_stamp(dest, source)
        (dest / "scripts" / "__pycache__").mkdir(parents=True)
        (dest / "scripts" / "__pycache__" / "x.pyc").write_bytes(b"\0")
        self.assertEqual(tree_hash(dest), tree_hash(source))
        (source / "SKILL.md").write_text("two\n", encoding="utf-8")
        self.assertEqual(skill_keep(dest, source), 1)

    def test_skill_hash_prints_only_the_hash_the_shell_writes_on_line_two(self) -> None:
        source = self.tmp / "src"
        source.mkdir()
        (source / "SKILL.md").write_text("one\n", encoding="utf-8")
        out = self._capture(lambda: main(["skill-hash", str(source)]))
        self.assertEqual(out, tree_hash(source) + "\n")

    def _capture(self, call) -> str:
        import io
        from contextlib import redirect_stdout
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            call()
        return buffer.getvalue()

    def test_set_factory_needs_an_overlay(self) -> None:
        import io
        from unittest.mock import patch
        body = json.dumps({"layer": "factory", "values": {"identity": "Ada"}})
        with patch("sys.stdin", io.StringIO(body)):
            code = main(["set"])
        self.assertEqual(code, 1)

    def test_a_save_keeps_a_key_this_brain_does_not_know(self) -> None:
        import io
        from unittest.mock import patch
        root, _project = self._root()
        env = root / ".ai-root" / "environment.json"
        env.write_text(json.dumps({"workflow.future.agent": "x", "label": "old"}), encoding="utf-8")
        body = json.dumps({"layer": "environment", "root": str(root), "values": {"label": "new"}})
        with patch("sys.stdin", io.StringIO(body)):
            self.assertEqual(self._capture(lambda: main(["set"])).strip(), str(env))
        self.assertEqual(json.loads(env.read_text(encoding="utf-8")), {"workflow.future.agent": "x", "label": "new"})
        body = json.dumps({"layer": "environment", "root": str(root), "values": {"bogus": "1"}})
        with patch("sys.stdin", io.StringIO(body)):
            self.assertEqual(main(["set"]), 1)

    def test_deleted_skill_folders_are_retired_or_shipped(self) -> None:
        repo = Path(__file__).resolve().parents[1]
        log = subprocess.run(
            ["git", "-c", "safe.directory=*", "-C", str(repo), "log", "--diff-filter=D", "--name-only", "--pretty=format:", "--", "skills", "vscode-global/skills"],
            capture_output=True, text=True, check=False,
        )
        if log.returncode != 0:
            self.fail(log.stderr or "git log failed")
        retired = (repo / "skills" / "RETIRED").read_text(encoding="utf-8")
        names = set()
        for line in log.stdout.splitlines():
            parts = line.replace("\\", "/").split("/")
            if parts[0] == "vscode-global":  # the skills' home before they moved to the root
                parts = parts[1:]
            if len(parts) >= 2 and parts[0] == "skills":
                names.add(parts[1])
        # Skills an owner's overlay retires (it shipped them last), by sha256 so their names stay
        # out of the base repo.
        overlay_retired = {"99678e7fe6cc7a459a33ccbd1d4a3b7c0a29637cfdb42eadcaec52f906f4d16d"}
        missing = []
        for name in sorted(names):
            if name in ("RETIRED",) or hashlib.sha256(name.encode()).hexdigest() in overlay_retired:
                continue
            shipped = (repo / "skills" / name / "SKILL.md").is_file()
            if not shipped and name not in retired:
                missing.append(name)
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
