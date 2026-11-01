# Type specimens in Godot

What we learned rendering fonts we do not commit (`game/ui/specimens/`). The choice itself is in
[typography](../design/typography.md).

| Subject | Finding |
| --- | --- |
| Loading a font from outside the project | `FontFile.new().load_dynamic_font(absolute_path)` returns `OK` and needs no import, so a specimen can use licensed or undecided fonts from the workspace `refs/fonts/` without committing them. A missing file returns an error; the specimen warns and falls back to the engine font |
| Variable fonts | Wrap the `FontFile` in a `FontVariation` and set `variation_opentype` with integer tag keys. `TextServer.name_to_tag()` is not static: call it on `TextServerManager.get_primary_interface()` |
| Letter spacing | `FontVariation.spacing_glyph` (pixels) is the tracking; duplicate the `FontVariation` to track one label differently, the base `FontFile` is shared |
| Layered neon | Three labels with a transparent fill and a wide, translucent `outline_size` (30, 16, 7 px at alpha 0.1, 0.22, 0.45) under the lit label give a glow with a hot edge, with no shader and no screen copy, so it is safe in Compatibility and on the web |
| Right-aligned numbers | `Label.get_minimum_size()` is valid straight after `add_child`, so a number can be placed by its right edge without a container |
| Command line | User arguments after `--` arrive in `OS.get_cmdline_user_args()`; Movie Maker names frames `<name>` plus eight digits (`marquee00000002.png`), and also writes a `.wav` |
| Judging a face | Render the real words: Atomic Age looked right in a specimen line but its G reads as J in DEADNIGHT. Test the title, the digits 0-9 and a settings label, not the alphabet |
