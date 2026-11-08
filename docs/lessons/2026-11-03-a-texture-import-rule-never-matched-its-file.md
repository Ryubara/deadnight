# A texture import rule written for one file never matched it

2026-11-03

- **Symptom:** a rule `("game/assets/smallmap/chalk_messages.png", TILING)` in `tools/check_texture_imports.py` still
  wrote `mipmaps/generate=false` for that texture.
- **Cause:** `ensure_import` asks `wanted()` with the path of the `.import` file, not of the image, so a pattern that
  ends in `.png` never matches; the existing rule (`textures/*`) matched only by its wildcard.
- **Fix:** end a single-file rule in `*` (`chalk_messages.*`) and read the written `.import` after a build.
- **Documented:** [Palette imports](../design/style.md#palette-imports); the kit's
  [surface materials](https://ryubara.github.io/gdstudio/engines/godot/surface-materials/) page has the import
  settings to keep.
