"""Run the projects page: python <brain>/engine/projects-page.py [options] (`aicf projects`).

A script puts its own folder first on sys.path, never the caller's working directory: a project
with its own `engine/` package cannot shadow the brain's. `python -m` would.
"""

import os
import sys

BRAIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path[0:1] = [BRAIN]

from pathlib import Path  # noqa: E402

from engine.projects_page.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:], Path(BRAIN)))
