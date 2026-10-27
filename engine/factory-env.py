"""Run the factory-config command: python <brain>/engine/factory-env.py <command> [args].

A script puts its own folder first on sys.path, never the caller's working directory: a project
with its own `engine/` package (game engines) cannot shadow the brain's. `python -m` would.
"""

import os
import sys

sys.path[0:1] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__)))]

from engine.factory_env.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
