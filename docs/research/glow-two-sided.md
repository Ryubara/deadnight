# Glow and window quads are seen from both sides

Issue #701: the lit windows of the concession showed only from the field; from inside you saw through them.

## What was wrong

`GlowPane` was a `QuadMesh` on a `StandardMaterial3D` (additive, unshaded) with Godot's default `cull_mode`
(back faces culled). A quad faces +Z; the pane sits in the north wall turned to face the field, so a player in the
room looked at its back and the renderer skipped it. Every other glow of the game (`glow.gdshader`: halos, pools,
the small map's `LightCards`, `DoorGlow`) already says `cull_disabled`, so the pane was the one see-through, flat mesh
a player could stand behind that was one-sided.

## The fix and what it looks like

`cull_mode = Disabled` on the pane's material. An additive pane draws one face at a time (the camera sees one side),
so the glow is not doubled; from inside the pane is lit glass that warms the night beyond it.

| Before (inside) | After (inside) |
| --- | --- |
| the pane is culled: the field shows plain through the opening | the pane shows as warm lit glass over the field |

Captures: `game/tests/captures/glow_pane_views.tscn` (`--view=out|in|beside|wall`, `--window=WindowW|WindowE`).

## Rules for the next glow or window

- A flat see-through mesh (a pane, a card, a sign face) a player can reach the back of is double-sided: a standard
  material with `cull_mode` Disabled, or a shader with `cull_disabled`. `test_glow_two_sided.gd` checks every such mesh
  of the drive-in and the small map's greyboxes and the glow scenes; a closed vessel (the soda glass) keeps back-face
  culling, its far wall shows through its near one.
- Two-sided means it can show through a wall if it overlaps one: a pane lies in its opening, not in the brick. The
  test samples the pane's face against every wall box of the lot.
- Capture a flat glow from **behind** as well as from the front before calling it done.
