# Wall weapons show their silhouette (#829)

Every wall weapon spot (both maps, the grenade rack too) shows the weapon's silhouette on its amber plaque instead of its
name. The name and the price come with the prompt card when a player is in reach (`NightTuning.use_reach`, 3.2 m), as
before. The genre's wall outline is the reference for the mechanic only; the look is Deadnight's: a flat dark-brown
stencil (the colour the name was) on the plaque that glows amber, so it reads in the dark.

## The rule

`SilhouetteMesh` (`game/world/shop/`) makes the shape from the weapon's own glb, never by hand:

1. The weapon id comes from the spot's shop id (`weapon_rifle` is `rifle`, `grenades` is `grenade`).
2. The model is its own hold file's (`holds/<id>.tres`), else `assets/weapons/<id>/<id>.glb` by folder. It is **not** the
   weapon's class hold: `WeaponHoldMap.hold_for` hands a weapon with no file of its own the class's model (the rifle's
   for a ray gun), which would hang the wrong gun on the wall. The three models of #816 (service pistol, ray gun, freeze
   gun) are found this way before they have a hold file or a spot.
3. Every surface of every mesh is laid along the plaque with the barrel pointing right (the HUD's rule,
   `WeaponSilhouettes.turn_to_the_right`), squashed to 1 mm and merged into one surface with `SurfaceTool.append_from`
   (native, one call a surface). The size follows the weapon's length (`WeaponSilhouettes.share_of_length`: the longest
   fills 1.5 m of the 1.7 m plaque, none under 58 percent of that), so a revolver reads as a revolver.
4. A plaque that stands on end (the second map's rifle cabinet, `upright`) lays the weapon along its long side, barrel up.
5. A weapon with no model yet gets a plain firearm shape (`stand_in`), not text.

`WallSilhouette` is the node the generators (`tools/world/build_greybox.py`, `build_smallmap_*.py`) write where the sign
was: `shop_id` and `upright`, nothing else. A new weapon gets its silhouette with its hold file (or its folder) and a
spot line in the map's generator; `test_wall_silhouettes.gd` fails for a wall spot with no silhouette, a label hanging
by a plaque, a model in `assets/weapons/` without a silhouette, and a prompt that names the weapon from beyond reach.

## Why a mesh and not the HUD's texture

The HUD's silhouettes draw each model into a `SubViewport` once. For the world that would be a render pass and a shader
per weapon at load (the web's cost is programs, [web export](web-export.md#loading-a-night-509)), a texture per
weapon, and a draw per spot. The mesh is built from data already loaded, shared by every spot of the weapon (the small
map sells the shotgun twice), drawn in one call, and needs no frame. The meshes are kept on the map that shows them
(`SilhouetteMesh.of`), not in a static, and the material is loaded, not preloaded: a static or a const preload held them
until the script went at exit and CI's exit-leak gate failed (#837).

## What it costs

Measured in the real renderer, desktop, 1920 x 1080 (`tests/captures/wall_silhouette_cost.tscn`: one camera 4 m from each
plaque, the silhouette, the old sign (a `Label3D`, 60 px with its outline) and neither, lowest of five frames each):

| | Drive-in lot (3 spots) | Second map (9 spots, 8 meshes) |
| --- | --- | --- |
| Draw calls added by a plaque in view | silhouette **1**, old sign **2** | silhouette **1**, old sign **2** |
| Primitives added by a plaque in view | 1,108 (average), sign 27 | 830 (average), sign 27 |
| Triangles made for the map | 3,324 | 7,472 |
| Meshes built at load (models already loaded) | 20 to 26 ms | 37 to 45 ms (first mesh 11 ms, the others 3 to 4 ms each) |
| New shader programs | 0 | 0 |

- **Draw calls go down**, one per plaque in view: a `Label3D` with an outline draws two surfaces, the silhouette is one.
  A phone's frame loses a call per plaque; it gains about 1,000 flat triangles of an unlit surface (a frame draws
  14,000 to 145,000).
- **No new program.** The material is unshaded, opaque, back-face culled, with no texture: the key
  (`DrawLedger.material_key`) of flat materials the night already draws. With culling off (the first try) it was a new
  program. A test holds the key. The mirror that puts the barrel to the right also reverses the depth axis (scale
  `-THICKNESS`), so the faces that look at the viewer keep their winding and culling the backs is right.
- **The meshes are built when the map enters the tree**, behind the loading bar, from glbs the warm-up loads for the
  Soldier's hands anyway. 20 to 45 ms on a development machine; the browser build is slower by a few times, which is
  about 0.1 to 0.2 s of a load of 20 s or more. Not measured in a browser: a change of that size is under the web
  smoke's noise (`night_load_baseline.json`), so it is the number here and not a gate.

## Looked at from the player's camera

Captures of both maps, far (7 and 12 m, silhouette only, no card) and near (the card names and prices it), on a desktop
(1920 x 1080) and a phone (2340 x 1080 with the touch layer, and 844 x 390), are attached to the pull request.
`tests/captures/wall_silhouette_tour.tscn` takes them (`--map=drive_in|small_indoor`, `--touch`); the player stands to the
left of the plaque so the body is not in front of it, and where a wall has no room behind the player (the grenade
rack's alley) the far look is from along the wall.
