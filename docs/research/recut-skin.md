# The re-cut skin

Issue #787: a re-cut weapon has to look different for as long as it is held, "alien, futuristic", the way the genre's
upgrade station changes a weapon. This page is what the genre does and why it reads, what we built (our own look, no
copied camo) and what it costs on the web build and a phone. The rules of the re-cut are on
[the re-cut and the hearty tonic](../design/upgrades.md); the look is in
[the re-cut skin](../design/upgrades.md#the-re-cut-skin).

## What the genre does (studied, not copied)

Source: the community wiki's
[Pack-a-Punch machine, Treyarch page](https://callofduty.fandom.com/wiki/Pack-a-Punch_Machine/Treyarch), read through
its API; the rest is what the pictures show. Design only: the patterns, colours and names below are theirs, ours are
below.

- **The upgrade changes the weapon's whole surface**, not a badge: the metal is re-textured and the furniture mostly
  kept, so the player can tell an upgraded weapon from across a room and in a teammate's hands.
- **One look per map or game**, not per weapon: stainless steel with engraved calligraphy (the first game), a black
  finish with red circuitry (the second), a meteorite blend of dark blue, red and yellow, lava-cracked black with
  alchemy symbols, an ice-like pale blue, gemstone colours, dragon scales in randomly picked colours, a galaxy in four
  colour variants. One game gives two looks per map, one for the first upgrade and one for the next. So a game ships a
  handful of looks, at most one per place, and every weapon wears the one of the place.
- **Patterns the eye reads as "tech" or "magic"**: circuits, cracks, scales, engraving, space. Dark base, a few
  saturated lines and a colour that is not in the world around it (the world is brown, olive and grey; the skin is
  not).
- **The cheap version exists for weak hardware**: the console version with the least memory got a simpler green skin
  with yellow engraving, "much like a real circuit board", instead of the full one (same page). The pattern is a
  texture on the weapon's own UVs in the genre, so every weapon is a texture job; that is what we avoid.
- **The rest of the upgrade is told with the look**: a pitched fire sound and a red-purple muzzle flash. The skin is
  one of three signals, not alone.

## What we built

A shader over the weapon's palette material, so a new model (#795 to #797) needs nothing:

- `recut_skin.gdshader` stands in the surface's `StandardMaterial3D` (the palette texture, metallic and roughness are
  copied by `RecutSkin`), so the weapon is the same surface and the same draw call as before. A material overlay was
  rejected: it draws every surface twice, and the phone's budget is draw calls
  ([phone frames](phone-frames.md)).
- **Base**: the palette pulled toward ink blue (the swatches' brightness is kept, so a grip, a barrel and a brass band
  still read apart), metallic 0.85, roughness 0.32: it catches the lot's lamps like chrome.
- **Cells**: a lattice of diamonds across the whole weapon, from the model's coordinates (not its UVs, which are a
  palette), flat to the face's own axis. Each edge is wired or not (a hash), so it reads as circuit traces and not a
  grid; a fifth of the cells burn and blink at their own rate.
- **Pulse**: a white-cyan band runs down the barrel (butt to muzzle) every couple of seconds and lights the traces it
  crosses.
- **Rim**: a fresnel rim in cold cyan with a violet fringe at the very edge: the colour that says "upgraded" at a
  distance, where from the shoulder camera a weapon is a few dozen pixels wide.
- **Breath**: a slow pulse (0.3 Hz) over the glow.
- **Ignition**: `reveal` sweeps the skin on from the butt to the muzzle with a white front and a flash (`boost`):
  0.7 s in the hand when the re-cut is bought, 0.55 s on the bench's cradle from the strike.
- One variant. The genre ships several looks because it has many maps; we have one skin for the lot and the small
  map. `RecutStyle` (an inspector resource) holds the colours and the pace, so #794's per-weapon re-cuts or another map
  can ship a second style with no new shader.

Not copied: no circuit board, cracks, scales or galaxy pattern; our diamond lattice, cold blue and violet fringe are
ours, drawn from the drive-in's own colours (the cold blue of the lot's night against the booth's amber).

## The switch

The frame already carries each player's weapons with their tier (`arms[weapon][2]`), so no wire changed:
`WeaponEquipSync` reads the tier of the weapon in each player's hand and calls `PlayerAnimation.set_recut`, which
tells `HeldWeapon` (the one builder the night's bodies and the menu's stage share). Every client does the same from the
same frame, so the player's own body, the others' bodies and a late joiner agree. A weapon equipped already re-cut
shows finished; one re-cut in the hand ignites. `HeldWeapon.recut` is kept across weapons, so the next weapon in the
hand is dressed the same until the sync says otherwise. The skin is on the surface, and `RecutSkin.strip` puts back
each surface's own material. A far level of detail (a `__far` mesh) is covered too, as it is any mesh under the
weapon. Pinned by `tests/weapons/test_recut_skin.gd` (every weapon model, the surfaces, a made-up model, the flash,
the uniforms) and `tests/night/test_weapon_recut_view.gd` (a real night: the buy, a swap away and back, another
player's body, a weapon lost).

## The bench

The bench keeps its projection-booth look (brass, iron, film reels, amber lamps) and changes at the blow: the press'
head, the five lamps and the bench's one light go from amber to the skin's cold blue, a flat ring of light leaves the
cradle (unshaded, additive, drawn only while it shows), the sparks burn the skin's colour and the weapon's skin sweeps
on from butt to muzzle in 0.55 s; the amber returns at the end. No light is added (the booth's budget is
`test_lot_light_cap`'s: the bench's one lamp is counted there, and `test_machines.gd` pins that it is still one).

## What it costs

- **Draw calls: none.** The skin stands in the surface's material; `test_recut_skin.gd` checks the surface count is the
  same with and without it and that no mesh has an overlay or override.
- **Lights: none.** The skin is a lit opaque surface like the palette material it replaces; it uses the lot's lights as
  that does (`test_the_skin_asks_for_no_light_and_no_blending`: no blend, no unshaded, no screen or depth read, one
  texture read).
- **Fill**: one palette read, a few hashes, two sines and a pow per pixel, on a surface that is a fraction of a percent
  of the screen.
- **First use**: a new shader is a new GL program the first time it is drawn, the hitch
  [first-use hitches](first-use-hitches.md) is about; the warm-up draws a re-cut copy of every weapon scene on its stage
  in each light condition, so the first re-cut of a night does not stop a frame.

Measured with `tools/web_smoke/recut_cost.py` (the web export of `tests/captures/recut_cost_bench.tscn`: 20 zombies
running the lot and 10 re-cuttable weapons held out in front of the camera, large and near, more than a night shows;
medians of 3 runs, interleaved):

| Profile | Skin | Frame ms (mean) | p95 ms | Draw calls |
| --- | --- | --- | --- | --- |
| Desktop Chrome, this GPU, unpaced | off | 3.24 | 6.00 | 109.0 |
| | on | 2.96 | 4.60 | 107.4 |
| Phone stand-in: SwiftShader (fill bound), CPU x4 slower | off | 253.4 | 431.1 | 111.0 |
| | on | 246.5 | 373.6 | 111.0 |

The skin is inside the run-to-run noise in time (the "on" arm was not slower in either profile) and adds no draw call
(111.0 and 111.0 on the phone profile; the desktop's 109 and 107 are the crowd's own variation). The numbers are
ratios inside one page, never a phone's frame rate ([phone frames](phone-frames.md#how-the-phone-was-stood-in-for)).
The browser console printed no error in any of the twelve cells, so the shader compiles and draws in WebGL2. A capture
of the bench page in Chrome with the skin on is attached to the pull request.

## Captures

Each weapon before and after, on the player view from the shoulder and from the side (`tests/captures/recut_sheet.tscn`);
the bench (`tests/captures/machines_tour.tscn --bench`); attached to the pull request.
