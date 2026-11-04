# Out of bounds: the way back to the start

A player who gets past every wall of a map (a prop added later, a physics glitch, a desync) used to stand on the
320 m `Outskirts` slab, 0.5 m under the lot, safe for the rest of the night, with no zombie path and no way back
(issue #862, after the plaza escape of #845). The maintainer chose to keep the slab (the menu stage and the captures
draw it for the horizon) and to put such a player back on the start. The rule is the server's.

## The rule

- **Bounds** (`PlayBounds`, `gameplay/night/play_bounds.gd`): the footprint, seen from above, of every solid
  (`use_collision`) box or cylinder of the map's scene except the piece named `Outskirts`: floors, aprons, fences,
  walls. A player whose feet are over none of them is out; so is one more than 6 m under the lowest piece (the second
  map has no slab under it, so a player outside it falls). Read from the scene when the night builds the world, never
  written by hand: a wall that moves moves the bounds. A scene with no solid piece has no bounds and nobody is out.
- **Why the footprints and not a box around the map:** the lot is not a rectangle (the road sticks out south, the
  aprons stick out at the corners), so a box leaves places past the wall inside it. A test asks the physics at every
  metre around each map (`tests/world/test_play_bounds.gd`): where the first solid thing under a point is the map's
  own the bounds say inside, where it is the slab or nothing they say outside, and the two agree at every point of
  both maps.
- **Return** (`NightServer._return_strays`, after the players are moved each tick): a body out for
  `NightTuning.out_of_bounds_seconds` (0.5) is put by `Player.teleport` on the start marker it came in on, at rest.
  Bots are bodies like any other and are returned the same way. The rules' state is not touched: a player on the
  ground is still on the ground with the bleed-out running; health and the revive hold are as they were. The wait is
  a grace, so a body that comes back in by itself starts the count over.

## What the clients do

- The player's own body: the server's position is in the next frame and the reconciler snaps over an error longer than
  `Reconciler.SNAP` (2.5 m), so the body is back at once; the camera snaps past `PlayerTuning.snap_distance`. The
  night also resets the body's physics interpolation on such a snap, so it is not blended across the map.
- The others: `RemoteAvatars` interpolates between two frames 33 ms apart, which drew the avatar sliding 25 m across
  the lot. A move of more than `RemoteAvatars.JUMP` (6 m) between two frames is marked in the track and held, not
  lerped, and the avatar's walk speed is not read from it. The net test failed with a 25.9 m glide before this.

## Tests and captures

`tests/world/test_play_bounds.gd` (bounds, both maps), `tests/night/test_out_of_bounds.gd` (the rule on the real body
past each wall of both maps with every door sold, the grace, nobody inside touched, a downed player, a bot, the
second player's own marker), `tests/net/test_out_of_bounds_online.gd` (over a WebSocket on both maps: the frame, the
other screen's avatar, the played body and its camera). The capture `tests/captures/out_of_bounds_return.tscn`
(`-- --map=small_indoor` for the second map) shows the body past the fence and back.

A spot the test used inside the second map turned out to be the snow bank of its yard (a 3.8 m solid box): a body
put in a solid is pushed out by the engine, which is not the rule moving it.
