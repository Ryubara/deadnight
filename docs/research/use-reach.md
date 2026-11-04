# Use reach: distance, side and sight

Deadnight #831, 2026-11-03. The maintainer: "double check collision detectors e.g. that we don't get prompted to
interact with an object through walls". Every thing a player can use is judged by one server call, and the prompt a
client draws is that call's answer.

## Where a use is decided

`NightServer.use_target(player_id)` answers `{}` or a dictionary with a `kind`. The frame carries it as the player's
`prompt` (so the card on the HUD is the server's, never a second opinion), and `_use` (the press) and `_hold_repair`
call it again, so the press can never differ from the prompt. A revive comes first; of the rest, a breach whose held
repair is going on keeps the prompt, and otherwise the one the player looks at wins (`UseOffers.faced`,
[spacing](#spacing-and-the-press-908)). Each zone's test is one function of `UseZones`, which the offers and the
spacing sweep both call:

| Kind | Where it is decided | Reach |
| --- | --- | --- |
| revive (a downed teammate) | `ReviveChannel.in_reach`, also the held channel | `revive_reach` flat |
| purchase door | `UseOffers.door` | `use_reach` (2.5 m) flat from a slab's middle, same floor, the door's open side |
| wall weapon, locker, crane, rack, re-cut bench, perk machines (the soda fountain's tonic) | `NightServer._spot_offer` (spots are the scene's `ShopSpots` markers) | `spot_reach` (1.5 m) from the marker, where the player stands; same floor |
| breach (boards) | `UseOffers.post` | `use_reach` from the gap's middle, same floor, inside the field |
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
- A breach's prompt came after the spots' in `use_target`: next to a wall weapon the board prompt never showed. That
  order was left as it was here, and it is the cause of #908 (below).

## Spacing and the press (#908)

Deadnight #908, 2026-11-03. The maintainer, at round 12 with three bots: "sometimes I'll be boarding something, and
then I'll accidentally interact with a weapon on the wall or a perk or something else next to it, the interactions need
to be properly spaced with one another to prevent accidental inputs and losing your weapons."

**Cause.** Three things together. Every use reached 3.2 m (`use_reach`, set by the first playable night and never
revisited), so a zone was a disc 6.4 m across, and nothing kept two of them apart: the lot's spot test asked for 3.2 m
between spots (one reach, not two) and left out breaches, and the second map had no such test. Where a window's zone
and a wall weapon's or a machine's met, `use_target` took the first match in a fixed order (a door, then any shop spot,
then the breach), so the weapon won wherever both reached, whatever the player looked at. And a gun bought with the
hands full replaced the one in hand on one press. A person mending a window taps use again to go on (the hold stops
when the window is whole or a board is torn off); a tap from a place in the weapon's reach bought it.

The sweep below found, with the old reach, 7 overlapping pairs on the lot (two doors with their breaker posts, the
rifle with the booth's door, the plaza's machines) and 51 on the second map: its wall weapons beside its windows (the
revolver with `start_1`, the bat with `upper_a2`, the flare gun with `upper_a1`), its perk machines 2.1 to 2.9 m from
each other and from the wall weapons, a locker 1.45 m from a window.

**The rule.**

- Two use zones never share ground, with `UseZones.MIN_GAP` (0.5 m) of floor between: a step off one never lands in
  the next. A zone is the floor a body stands on from which the server offers the thing (reach, floor, line from the
  hand, side). For two things in the open that is a distance between them of the two reaches and the gap: 3.5 m between
  two shop spots' markers, 4.5 m between a spot's marker and a slab, breach or post, 5.5 m between two of those.
- The reaches are what a hand needs, not more: `spot_reach` 1.5 m from a spot's marker (the marker is where the player
  stands), `use_reach` 2.5 m from a door's slab, a breach or a post (their stands are 1.4 to 1.5 m out, and a bot comes
  within a metre of a stand).
- Where two zones still meet (a teammate down beside a door, a map in progress), the one the player looks at wins; a
  breach keeps the prompt while a held repair of it goes on.
- No purchase from a repair (`UseGuard`): while a held repair goes on, and for `repair_grace` (1.5 s) after its last
  board, a press buys nothing. A purchase that would replace a weapon carried takes a press made once its card (which
  names what goes) has been the prompt for `replace_settle` (0.4 s). Free uses (boards, breakers, revives) are never
  held back, and a weapon bought with a hand free is one press as before.
- Bots use the same rules: at a stand a bot looks at what it buys (a door's slab, the thing in front of a spot's
  marker), and it walks onto the stand itself while the card is not up (it used to stop half a metre short, which the
  old 3.2 m reach forgave).

**The test.** `game/tests/world/test_use_zone_spacing.gd` walks a 0.25 m grid of standing ground round every
interactable of both maps, each zone grown by half the gap, and fails on a point inside two. The lot passes after three
moves in `tools/world/build_greybox.py`: the booth's post to 5.6 m east of the door (was 4.6), the back lot's post to
6 m east of the gate (was 4.5), the rifle 0.5 m further west. The second map's 26 remaining pairs are all places its
rework moves ([#917](https://github.com/Ryubara/deadnight/issues/917): one window a wall, the upper windows on a patio,
each perk in its own corridor): they are listed in the test, which fails on any other pair and on a listed pair that no
longer overlaps, so the list only shrinks. `game/tests/night/test_use_guard.gd` presses through the real night: a tap
after a board, at the shotgun, buys nothing until the grace is over; a press edge during a held repair at a weapon buys
nothing; a replacing gun is kept on a press the moment its card shows and bought once it has been read; a gun with a
hand free is one press.
