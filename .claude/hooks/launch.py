"""Runs the GDStudio kit's hook dispatcher for this game (the kit's docs/hooks.md).

The guards live once, in the kit (`<workspace>/repos/gdstudio/.claude/hooks/`), so every game shares them. This
launcher finds the workspace by its marker file and hands the hook input to the kit's dispatcher. Without a workspace
or a kit it lets the call through and says so: run the kit's bootstrap.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

start = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2])
workspace = next((f for f in (start, *start.parents) if (f / ".gdstudio-workspace").exists()), None)
dispatcher = workspace / "repos" / "gdstudio" / ".claude" / "hooks" / "dispatch.py" if workspace else None
if dispatcher is None or not dispatcher.exists():
    sys.stderr.write(
        "gdstudio hooks: no GDStudio workspace with the kit found; run the kit's bootstrap (call allowed)\n"
    )
    sys.exit(0)
sys.exit(subprocess.run([sys.executable, str(dispatcher)], input=sys.stdin.buffer.read(), check=False).returncode)
