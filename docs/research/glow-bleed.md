# Glows and lights stay on their side of a wall

Issue #832 (the maintainer: light must not bleed through walls, and one sign's glow halo did).
The Compatibility renderer casts no shadow, so a halo, a pool or a cone of haze is an additive quad that only the depth
test hides, and a lamp is an unshadowed light. Each reaches into the next room as soon as its card, or its range, does.

## What was wrong with the SNACKS sign

Measured with the sign's light and halo hidden and shown, from inside the stand (`tests/captures/neon_halo_tour.tscn`,
`--hide=Light` or `--hide=Halo`):

| Part | Before | Cause |
| --- | --- | --- |
| `Light` (omni, energy 9.6, range 10, 1.2 m outside the wall) | changed 140 000 to 270 000 pixels of every room view: the floor and the roof pink, up to 3.1 energy on the floor and 2.3 on the roof | an unshadowed omni lights whatever its sphere holds, wall or not |
| `Halo` (flat 9 x 4 m card, centre 3.3 m high) | 13 600 pixels from the roof behind the wall: a pink band in the air over the roof's edge | the card is taller than its wall (the wall stops at 4 m, the card runs to 5.3 m) |

The halo's billboard fault was already cured by hand in #703. The scene's halo energy (0.325) is only a first value:
`LotNeonSign._apply` sets it every tick from `LightTuning.neon_halo_energy` (0.9), which is the "0.325 against 0.9".

## The fix

- **The sign's light is a spot facing out** (`lot_neon_sign.tscn`): a spot's cone never reaches behind the plane its apex
  stands in, so nothing behind the sign gets light, with no shadow and the same single light slot. Energy 16 and angle
  85 degrees give the field the same pink ground as the omni did (mean colour of the ground in the front view 169, 83, 95
  against 163, 82, 91). The wash on the brick far from the sign is gone (it came from the omni); the halo card keeps the
  glow round the letters.
- **Glow cards carry two world-space clip planes** (`clip_a`, `clip_b` in `glow.gdshader` and `beam.gdshader`: a point is
  not drawn where `dot(point, xyz) > w`; zero normal = off). `GlowClip` finds them from the wall boxes:
  `planes_around` for a lamp that stands in front of a wall (the small map's pendants and lanterns, the projector's
  lens halo against the booth's upper floor), `top_of_wall_behind` for a card mounted on a wall (the sign's halo stops at
  the wall's top, y = 4). A lamp placed beside a wall needs no number. No new draw call, no new shader program; two dot
  products a fragment.

## The check (`tests/world/test_glow_bleed.gd`, helper `glow_bleed.gd`)

- **Cards:** every additive mesh of both maps is sampled where its shader draws at least 5 % of its brightest (disc
  falloff, card edges, a billboard over every horizontal direction, the card's own clip planes). A point whose segment to
  its lamp (the light of its own fixture; else its own centre) crosses a wall box, or a point of a flat card mounted on
  a wall that has no wall within 1 m behind it, is a bleed. Points inside a wall's thickness are hidden and do not count.
  Windows, the light under a door, moon shafts and the projector's lens follow a lamp elsewhere on purpose and are tested
  from their own centre.
- **Lights:** each omni and spot is tested against the faces of floors, roofs, walls and ground (joints between boxes
  dropped): a face the lamp gives at least 0.15 energy (distance, angle, cone) with a wall between is a leak. The sign
  must have none; the others are in a table of what they leak today (the test fails if one grows, if another lamp
  leaks, or if a listed lamp stops).
- Both halves have a synthetic scene (a wall, a pool, an omni and a spot) so a check that sees nothing cannot pass.

## What was left, and what became of it

Unshadowed lamps inside a room lit the next room through the wall by their range (0.2 to 0.7 energy): the stand's three
lamps, the field's posts 5, 6 and 12, the booth's lower lamp and the second map's pendants. A light layer per room cured
all of it but three lines, in [room lights](room-lights.md) (issue #841). The projector's spot (`ProjectorBeam`) faced
the road and lit the booth's south door and the road plaza (0.9) through the booth's wall; issue #840 turned it.
