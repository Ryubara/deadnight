# Use reach: distance, side and sight

Deadnight #831, 2026-11-03. The maintainer: "double check collision detectors e.g. that we don't get prompted to
interact with an object through walls". Every thing a player can use is judged by one server call, and the prompt a
client draws is that call's answer.

## Where a use is decided

`NightServer.use_target(player_id)` answers `{}` or a dictionary with a `kind`. The frame carries it as the player's
`prompt` (so the card on the HUD is the server's, never a second opinion), and `_use` (the press) and `_hold_repair`
call it again, so the press can never differ from the prompt. In order:

| Kind | Where it is decided | Reach |
| --- | --- | --- |
| revive (a downed teammate) | `ReviveChannel.in_reach`, also the held channel | `revive_reach` flat |
| purchase door | `UseOffers.door` | `use_reach` flat, same floor, the door's open side |
| wall weapon, locker, crane, rack, re-cut bench, perk machines (the soda fountain's tonic) | `NightServer._spot_offer` (spots are the scene's `ShopSpots` markers) | `use_reach`, same floor |
| breach (boards) | `UseOffers.post` | `use_reach`, same floor, inside the field |
| breaker post | `UseOffers.post`, `LotSwitches.within_reach` | `use_reach` flat |
| fuel can | `UseOffers.fuel`, `LotFuel.within_reach` | `fuel_reach` flat |

Bots press through the same `apply` command path, so they get the same answer.

## The rule

A reach was a flat distance (and, on a map with a storey, a floor). Nothing asked what stood between the hand and the
thing, so a player on the other side of a wall within 3.2 m saw the card and could buy. `UseSight` (the server's, built
from `WorldProbe.static_callable`) now asks every one of the above:

- The line runs from the player's hand to the thing, both `UseSight.HAND` (1.1 m) above their floor, so a counter
  of 1 m is reached over and a wall is not.
- It is cast with the **static** probe: walls, props, doors and floors count; a person, a zombie or a thrown thing does
  not. The shots' probe also meets the bodies of players, and its ray stops on the target's own capsule (the kit lesson
  `2026-11-03-a-blast-aimed-at-a-player-found-the-player-in-the-way`).
- A spot's marker is where the player stands, so it needs `SKIN` (0.2 m). A thing that hangs in a wall (a breaker post,
  a door's slab, the window boards) is judged to `MOUNT_SKIN` (0.6 m, half a wall), and from the side its front faces
  only: a post from behind its wall, a door from behind itself, a breach from outside the fence are out of reach.
- Boards are on their own layer (`PhysicsLayers.BOARDS`), so a torn or whole board never blocks the line.

## The test

`game/tests/night/test_use_through_walls.gd` walks every interactable of both maps. Around each, on a polar grid of
standing points within its reach (rings of 0.5 m, a spoke every 12 degrees, a body's room clear), a ray of the test's own
sorts the points a wall (or the back of a door or post) is between from the clear ones. At the blocked points the
server must show no prompt for the thing and a press must change nothing; in front of it and at each clear point
within 1.6 m the prompt shows; the frame carries the server's prompt; a point on the other floor of the second map is
out of reach. A downed teammate is placed beside a wall at each spot and held on to from its far side. Doors are bought
in the shop's order, each walked while shut.

Before the change, on `main`: 910 prompts through walls on the two maps and 41 presses that bought or changed
something; both revive tests failed. The second map's floors were already guarded by `on_level`.

## Findings

- The oldest cases were the lot's wall weapons, the re-cut bench, the soda fountain and the lockers: all sit against
  the walls of a room, with a player's side of the wall 1.5 to 3 m from the marker.
- A body teleported next to a wall is pushed off by the physics step, which then judges a different point: a test that
  teleports a player keeps a body's room (0.5 m) clear round the point and checks the body stayed where it was put.
- A breach's prompt comes after the spots' in `use_target`: next to a wall weapon the board prompt never shows. That
  order is older than this change and is left as it is.
