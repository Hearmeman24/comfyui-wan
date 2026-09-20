#!/usr/bin/env python3
"""Run the template deployer from this template's pinned shared runtime."""

import subprocess
import sys

from validate_models import runtime_dir


if __name__ == "__main__":
    raise SystemExit(
        subprocess.run(
            [sys.executable, str(runtime_dir() / "tools" / "update_runpod_template.py"), *sys.argv[1:]]
        ).returncode
    )
