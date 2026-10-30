"""`aicf config`: code roots, the personal overlay, the skills scan, and a server that only
answers its own page (localhost is not a trust boundary)."""

from __future__ import annotations

import http.client
import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

from engine.config_ui import actions, overlay, roots
from engine.config_ui.cli import parse_args
from engine.config_ui.scan import scan
from engine.config_ui.server import ConfigServer
from engine.factory_env.schema import ConfigError

BRAIN = Path(__file__).resolve().parent.parent
ENV_NAMES = ("HOME", "AI_TEMPLATE_OVERLAY_DIR", "AI_WORK_ROOTS")


def _skill(folder: Path, name: str) -> Path:
    (folder / name).mkdir(parents=True, exist_ok=True)
    (folder / name / "SKILL.md").write_text(f"---\nname: {name}\ndescription: test\n---\n", encoding="utf-8")
    return folder / name


class Sandbox(unittest.TestCase):
    def setUp(self) -> None:
        self.saved = {name: os.environ.get(name) for name in ENV_NAMES}
        self.tmp = Path(tempfile.mkdtemp(prefix="config-ui-"))
        self.home = self.tmp / "home"
        self.home.mkdir()
        os.environ["HOME"] = str(self.home)
        os.environ["AI_WORK_ROOTS"] = "none"
        os.environ.pop("AI_TEMPLATE_OVERLAY_DIR", None)

    def tearDown(self) -> None:
        for name, value in self.saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        shutil.rmtree(self.tmp, ignore_errors=True)

    def folder(self, *parts: str) -> Path:
        path = self.tmp.joinpath(*parts)
        path.mkdir(parents=True, exist_ok=True)
        return path


class RootTests(Sandbox):
    def test_add_writes_the_environment_and_remembers_the_root(self) -> None:
        root = self.folder("Projects")
        roots.add_root(str(root), "side", "personal")
        data = json.loads((root / ".ai-root" / "environment.json").read_text(encoding="utf-8"))
        self.assertEqual(data, {"label": "side", "kind": "personal"})
        self.assertEqual(roots.recorded(), [str(root)])
        listed = roots.known_roots(self.folder("Code", "AICodeFactory"))
        self.assertIn(roots.key(root), [roots.key(item.path) for item in listed])
        self.assertTrue(next(item for item in listed if roots.key(item.path) == roots.key(root)).is_code_root)

    def test_a_project_or_a_relative_path_is_not_a_root(self) -> None:
        project = self.folder("Projects", "app")
        subprocess.run(["git", "init", "-q", str(project)], check=True)
        with self.assertRaisesRegex(ConfigError, "inside the git repo"):
            roots.add_root(str(project), "", "")
        with self.assertRaisesRegex(ConfigError, "not an absolute path"):
            roots.add_root("Projects", "", "")
        with self.assertRaisesRegex(ConfigError, "not a folder"):
            roots.add_root(str(self.tmp / "missing"), "", "")
        with self.assertRaisesRegex(ConfigError, "kind must be"):
            roots.add_root(str(self.folder("Other")), "", "office")

    def test_forget_keeps_the_ai_root_and_never_drops_the_brain_root(self) -> None:
        brain = self.folder("Code", "AICodeFactory")
        root = self.folder("Projects")
        roots.add_root(str(root), "", "")
        roots.forget_root(brain, str(root))
        self.assertEqual(roots.recorded(), [])
        self.assertTrue((root / ".ai-root" / "environment.json").is_file())
        with self.assertRaisesRegex(ConfigError, "always a root"):
            roots.forget_root(brain, str(brain.parent))
        with self.assertRaisesRegex(ConfigError, "was not added"):
            roots.forget_root(brain, str(root))

    def test_siblings_with_an_ai_root_are_found(self) -> None:
        brain = self.folder("Code", "AICodeFactory")
        self.folder("Work", ".ai-root")
        self.folder("Plain")
        found = [item.path.name for item in roots.known_roots(brain)]
        self.assertEqual(found, ["Code", "Work"])
        self.assertTrue(roots.known_roots(brain)[0].brain_root)


class OverlayTests(Sandbox):
    def test_set_writes_the_marker_and_rewrites_only_a_variable_already_there(self) -> None:
        mine = self.folder("mine")
        _skill(mine / "skills", "tidy")
        claude = self.home / ".claude"
        claude.mkdir()
        (claude / "settings.json").write_text(json.dumps({"env": {"AI_TEMPLATE_OVERLAY_DIR": "old"}, "x": 1}), encoding="utf-8")
        changed = overlay.set_overlay(str(mine))
        self.assertEqual((self.home / ".ai-template-overlay-dir").read_text(encoding="utf-8").strip(), str(mine))
        self.assertEqual(changed, [claude / "settings.json"])
        data = json.loads((claude / "settings.json").read_text(encoding="utf-8"))
        self.assertEqual(data, {"env": {"AI_TEMPLATE_OVERLAY_DIR": str(mine)}, "x": 1})
        now = overlay.current()
        self.assertEqual((now["path"], now["source"], now["skills"]), (str(mine.resolve()), "marker", ["tidy"]))
        overlay.clear_overlay()
        self.assertFalse((self.home / ".ai-template-overlay-dir").exists())
        self.assertEqual(json.loads((claude / "settings.json").read_text(encoding="utf-8")), {"env": {}, "x": 1})

    def test_a_bare_skills_folder_is_an_extra_folder_not_an_overlay(self) -> None:
        bare = self.folder("bare")
        _skill(bare, "tidy")
        with self.assertRaisesRegex(ConfigError, "extra skills folder"):
            overlay.set_overlay(str(bare))
        with self.assertRaisesRegex(ConfigError, "AICodeFactory itself"):
            overlay.set_overlay(str(BRAIN))


class ScanTests(Sandbox):
    def test_finds_skill_folders_and_skips_hidden_and_dependency_trees(self) -> None:
        _skill(self.folder("a", "skills"), "one")
        _skill(self.folder("a", "skills"), "two")
        _skill(self.folder("b", "node_modules", "pkg"), "dep")
        _skill(self.folder("b", ".claude", "skills"), "installed")
        _skill(self.folder("c", "d", "e", "f"), "deep")
        result = scan([self.tmp], depth=3)
        self.assertEqual([(Path(c["path"]).name, c["skills"]) for c in result["candidates"]], [("skills", ["one", "two"])])
        self.assertFalse(result["truncated"])
        self.assertEqual(len(scan([self.tmp], depth=6)["candidates"]), 2)

    def test_the_budget_stops_the_walk(self) -> None:
        for index in range(5):
            self.folder("many", str(index))
        self.assertTrue(scan([self.tmp], budget=2)["truncated"])


class ActionTests(Sandbox):
    def setUp(self) -> None:
        super().setUp()
        self.root = self.folder("Projects")
        roots.add_root(str(self.root), "", "personal")

    def environment(self) -> dict:
        return json.loads((self.root / ".ai-root" / "environment.json").read_text(encoding="utf-8"))

    def test_a_skill_switch_moves_the_name_between_the_lists(self) -> None:
        actions.run(BRAIN, "skill", {"root": str(self.root), "name": "tidy", "state": "off"})
        self.assertEqual(self.environment()["skills.off"], ["tidy"])
        actions.run(BRAIN, "skill", {"root": str(self.root), "name": "tidy", "state": "on"})
        self.assertEqual((self.environment().get("skills.off"), self.environment()["skills.on"]), (None, ["tidy"]))
        actions.run(BRAIN, "skill", {"root": str(self.root), "name": "tidy", "state": "default"})
        self.assertNotIn("skills.on", self.environment())
        with self.assertRaisesRegex(ConfigError, "state must be"):
            actions.run(BRAIN, "skill", {"root": str(self.root), "name": "tidy", "state": "maybe"})

    def test_extra_folders_must_hold_skills_and_show_up_as_used(self) -> None:
        extra = self.folder("extra")
        with self.assertRaisesRegex(ConfigError, "holds no skill"):
            actions.run(BRAIN, "environment", {"root": str(self.root), "values": {"overlays": [str(extra)]}})
        _skill(extra, "tidy")
        result = actions.run(BRAIN, "environment", {"root": str(self.root), "values": {"overlays": [str(extra), str(extra)]}})
        self.assertEqual(self.environment()["overlays"], [str(extra)])
        env = next(e for e in result["state"]["environments"] if roots.key(Path(e["root"])) == roots.key(self.root))
        self.assertIn("tidy", [s["name"] for s in env["skills"]])
        found = actions.run(BRAIN, "scan", {"folders": [str(self.tmp)]})
        used = {Path(c["path"]).name: c["used"] for c in found["candidates"]}
        self.assertTrue(used["extra"].startswith("skills folder of"))

    def test_scan_offers_a_skills_folder_parent_as_the_overlay(self) -> None:
        _skill(self.folder("private", "skills"), "mine")
        found = actions.run(BRAIN, "scan", {"folders": [str(self.tmp / "private")]})
        self.assertEqual(found["candidates"][0]["overlay"], str(self.tmp / "private"))
        with self.assertRaisesRegex(ConfigError, "at least one folder"):
            actions.run(BRAIN, "scan", {"folders": []})
        with self.assertRaisesRegex(ConfigError, "unknown action"):
            actions.run(BRAIN, "nope", {})


class ServerTests(Sandbox):
    def setUp(self) -> None:
        super().setUp()
        self.server = ConfigServer(BRAIN, "secret-token")
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        super().tearDown()

    def request(self, method: str, path: str, headers: dict | None = None, body: bytes | None = None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        payload = response.read()
        connection.close()
        return response, payload

    def test_the_page_needs_the_run_key_and_carries_a_strict_csp(self) -> None:
        self.assertEqual(self.request("GET", "/")[0].status, 403)
        self.assertEqual(self.request("GET", "/?t=wrong")[0].status, 403)
        response, payload = self.request("GET", "/?t=secret-token")
        self.assertEqual(response.status, 200)
        self.assertIn(b'content="secret-token"', payload)
        self.assertIn("default-src 'none'", response.getheader("Content-Security-Policy"))
        self.assertEqual(response.getheader("Cache-Control"), "no-store")

    def test_the_api_needs_the_header_token(self) -> None:
        self.assertEqual(self.request("GET", "/api/state")[0].status, 403)
        response, payload = self.request("GET", "/api/state", {"X-AICF-Token": "secret-token"})
        self.assertEqual(response.status, 200)
        self.assertIn("environments", json.loads(payload))

    def test_another_host_origin_or_site_is_refused(self) -> None:
        token = {"X-AICF-Token": "secret-token"}
        self.assertEqual(self.request("GET", "/api/state", {**token, "Host": f"evil.test:{self.port}"})[0].status, 403)
        self.assertEqual(self.request("GET", "/api/state", {**token, "Host": f"localhost:{self.port}"})[0].status, 403)
        self.assertEqual(self.request("GET", "/api/state", {**token, "Origin": "http://127.0.0.1:1"})[0].status, 403)
        self.assertEqual(self.request("GET", "/?t=secret-token", {"Sec-Fetch-Site": "cross-site"})[0].status, 403)
        self.assertEqual(self.request("GET", "/api/state", {**token, "Origin": self.server.origin})[0].status, 200)

    def test_a_post_must_be_json_and_reports_config_errors(self) -> None:
        token = {"X-AICF-Token": "secret-token"}
        self.assertEqual(self.request("POST", "/api/scan", {**token, "Content-Type": "text/plain"}, b"{}")[0].status, 415)
        self.assertEqual(self.request("POST", "/api/scan", {"Content-Type": "application/json"}, b"{}")[0].status, 403)
        response, payload = self.request("POST", "/api/scan", {**token, "Content-Type": "application/json"}, b'{"folders": []}')
        self.assertEqual((response.status, json.loads(payload)["error"]), (400, "give at least one folder to scan"))

    def test_an_idle_browser_connection_does_not_block_the_next_request(self) -> None:
        idle = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        idle.request("GET", "/app.css")
        idle.getresponse().read()   # kept open, like a browser's keep-alive or spare socket
        try:
            response, _ = self.request("GET", "/api/state", {"X-AICF-Token": "secret-token"})
            self.assertEqual(response.status, 200)
        finally:
            idle.close()

    def test_an_unexpected_failure_is_a_json_error_not_a_dropped_connection(self) -> None:
        original = actions.state
        actions.state = lambda brain: (_ for _ in ()).throw(PermissionError("denied"))
        try:
            response, payload = self.request("GET", "/api/state", {"X-AICF-Token": "secret-token"})
        finally:
            actions.state = original
        self.assertEqual(response.status, 500)
        self.assertIn("PermissionError: denied", json.loads(payload)["error"])

    def test_adding_a_folder_answers_the_environment_it_added(self) -> None:
        root = self.folder("Elsewhere")
        body = json.dumps({"path": str(root), "kind": "work"}).encode("utf-8")
        response, payload = self.request("POST", "/api/root-add", {"X-AICF-Token": "secret-token", "Content-Type": "application/json"}, body)
        data = json.loads(payload)
        self.assertEqual(response.status, 200, data)
        self.assertEqual(roots.key(Path(data["added"])), roots.key(root))
        env = next(item for item in data["state"]["environments"] if roots.key(Path(item["root"])) == roots.key(root))
        self.assertEqual((env["kind"], env["code_root"]), ("work", True))


class CliTests(unittest.TestCase):
    def test_options(self) -> None:
        self.assertEqual(parse_args(["--no-open", "--port", "8123", "--idle", "5"]),
                         {"open": False, "port": 8123, "idle": 5.0, "json": False})
        for bad in (["--port"], ["--port", "x"], ["--port", "70000"], ["--nope"]):
            with self.assertRaises(ValueError):
                parse_args(bad)


if __name__ == "__main__":
    unittest.main()
