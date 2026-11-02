"""Give a palette a build script has just saved its Godot `.import` (lossless, no mipmaps, Detect 3D off).

The rules live in `tools/check_texture_imports.py` (issue #441); this puts that file on the path for Blender's Python.
The build scripts import it after `bpy` so it runs inside Blender; it needs nothing but the standard library.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from check_texture_imports import ensure_import

__all__ = ["ensure_import"]
