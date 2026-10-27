"""Flat settings: a string or a list of strings. Nothing nested deeper than that.

The session-start sync reads these files only through this module.
"""

from __future__ import annotations

import json
import re

STEPS = (
    "design",
    "plan",
    "spec",
    "converge",
    "implement",
    "review",
    "review-prefilter",
    "verify",
    "devops",
    "offload",
    "learn",
    "chores",
)

# (agent, model, effort). review-prefilter is the optional free first pass.
DEFAULT_WORKFLOW: dict[str, tuple[str, str, str]] = {
    "design": ("claude", "inherit", ""),
    "plan": ("inherit", "inherit", ""),
    "spec": ("inherit", "inherit", ""),
    "converge": ("inherit", "inherit", ""),
    "implement": ("implementer", "sonnet", ""),
    "review": ("reviewer", "haiku", ""),
    "review-prefilter": ("mlx", "local", ""),
    "verify": ("verifier", "sonnet", ""),
    "devops": ("devops", "sonnet", ""),
    "offload": ("mlx", "local", ""),
    "learn": ("fable", "inherit", ""),
    "chores": ("helpers", "", ""),
}

SCALAR_KEYS = ("label", "kind", "claude_profile", "identity", "taste")
LIST_KEYS = ("overlays", "skills.on", "skills.off")
KINDS = ("personal", "work")
TOKEN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,40}$")
STEP_FIELD = re.compile(r"^workflow\.([a-z0-9-]+)\.(agent|model|effort)$")
IDENTITY_MAX = 200
TASTE_MAX = 2000


class ConfigError(Exception):
    """The file or the change is not valid. The message says what to fix."""


def load_json(text: str, label: str) -> dict:
    if text.strip() == "":
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"{label} is not JSON — fix it or replace it ({exc.msg})") from exc
    if not isinstance(data, dict):
        raise ConfigError(f"{label} must be a JSON object")
    return data


def known_key(key: str) -> bool:
    if key in SCALAR_KEYS or key in LIST_KEYS:
        return True
    match = STEP_FIELD.match(key)
    return bool(match and match.group(1) in STEPS)


def _as_list(value: object, key: str) -> list[str]:
    if value is None or value == "":
        return []
    if isinstance(value, str):
        return [part.strip() for part in value.split("|") if part.strip()]
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return [item.strip() for item in value if item.strip()]
    raise ConfigError(f"{key} must be a list of strings, or one string with | between items")


def _token(value: str, key: str) -> None:
    if value and TOKEN.match(value) is None:
        raise ConfigError(f"{key} must be a short name (letters, digits, . _ -), not {value!r}")


def validate_document(data: dict, *, kind: str = "", strict: bool = True, check_work: bool = True) -> dict:
    """Cleaned document. Strict set rejects unknown keys; a read skips them."""
    cleaned: dict = {}
    for key, value in data.items():
        if not isinstance(key, str) or not known_key(key):
            if strict:
                raise ConfigError(f"unknown setting {key!r}")
            continue
        try:
            cleaned[key] = _clean_value(key, value)
        except ConfigError:
            if strict:
                raise
    if check_work and (kind or cleaned.get("kind")) == "work":
        _reject_work_mlx(cleaned)
    return {key: value for key, value in cleaned.items() if value not in ("", [])}


def _clean_value(key: str, value: object):
    if key in LIST_KEYS:
        items = _as_list(value, key)
        if key.startswith("skills."):
            for item in items:
                _token(item, key)
        return items
    if not isinstance(value, str):
        raise ConfigError(f"{key} must be a string")
    value = value.strip()
    if key == "kind" and value and value not in KINDS:
        raise ConfigError("kind must be personal or work")
    if key == "label":
        _token(value, key)
    if key == "identity" and len(value) > IDENTITY_MAX:
        raise ConfigError(f"identity is longer than {IDENTITY_MAX} characters")
    if key == "taste" and len(value) > TASTE_MAX:
        raise ConfigError(f"taste is longer than {TASTE_MAX} characters")
    match = STEP_FIELD.match(key)
    if match and match.group(2) in ("agent", "model"):
        _token(value, key)
    if match and match.group(2) == "effort" and len(value) > 40:
        raise ConfigError(f"{key} is longer than 40 characters")
    return value


def _reject_work_mlx(data: dict) -> None:
    for step in STEPS:
        if data.get(f"workflow.{step}.agent") == "mlx":
            raise ConfigError(
                f"workflow.{step}.agent cannot be mlx in a work environment — "
                "MLX stays off for work and for security review"
            )


def dumps(data: dict) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"
