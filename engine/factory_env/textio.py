"""Text writing that runs on every Python the engine may find (macOS ships 3.9)."""

from __future__ import annotations

from pathlib import Path


def write_lf(path: Path, text: str) -> None:
    """Write ``text`` as UTF-8 with LF line ends — ``Path.write_text(newline=)`` needs 3.10."""
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
