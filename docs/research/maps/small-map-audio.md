# Small map: sound

What the second map sounds like and where every sound comes from (issue #657). The map: [the small indoor map](../../design/smallmap.md),
its look: [small map: art and kit](small-map-art.md). The game's sound rules (buses, levels, the voice budget) are
[Sound](../../design/audio.md); how sounds are made is [Audio](../audio.md).

## The idea

The first map is open air: a lot, a screen, crickets and a highway, the generator as the heartbeat. The second is a
shut-in depot on a cold, still night, so its sound is the opposite: **close, dry and low indoors, thin and far outside**,
and the only way to hear outside is through a window.

- **Indoors**, a room tone (the building's own air) under everything, one for each kind of room, and the wind through
  the broken roof upstairs.
- **Outside**, heard only through a window or a gap: wind in the bare trees, two fires burning in the distance, the
  hum of the power lines, the drive-in's road far off, and now and then a fence rattling. No crickets: it is frosted
  ground, nothing sings.
- **The pieces** make the sounds the first map's do, with the new ones the map needs: the dead tearing boards off a
  1.2 x 1.3 m window, a plank door unlocked, a pile of furniture and rubble dragged off a stair, feet on wood stairs.

## The sound list, and what each costs

Every sound is either already in the game, or **synthesised** by `tools/audio/` (our own work, committed, no licence
entry, no credits). Nothing here needs ElevenLabs credits to ship. The last column is the optional upgrade: what the
sound would cost if the maintainer judges the synthesised version short and decides to generate it
(40 credits for each second requested, [measured](../audio.md#the-dead-248); a sound is requested once and kept).

| Sound (id) | Where and when | Source | Credits now | Optional upgrade |
| --- | --- | --- | ---: | ---: |
| `bed_room_tone` | flat loop under every room, the level follows the room the listener stands in | synthesised (new, 20 s) | 0 | none (a tone) |
| `bed_roof_wind` | flat loop, only upstairs, louder under the broken roof | synthesised (new, 20 s) | 0 | none |
| `backdrop_wind` | 3D loops in the yard's corners, past the walls | synthesised (new, 24 s) | 0 | 880 (22 s loop) not worth it |
| `backdrop_fire` | 3D loop on each of the two fires (wreck, barrel) | synthesised (new, 12 s) | 0 | none |
| `backdrop_wire` | 3D loops at the pole lines, a thin hum and whine | synthesised (new, 12 s) | 0 | none |
| `backdrop_road` | the drive-in's road far off, one 3D loop in the north | the existing `bed_highway` file, a new definition with the reach of a far thing | 0 | none |
| `yard_rattle` | now and then (every 12 to 25 s) at a fence post or a coil, 3D | synthesised (new, 3 takes) | 0 | **240** (3 takes of 2 s) |
| `board_tear`, `board_last`, `board_repair` | at the window's opening, from `board_torn` and `board_repaired` | existing (synthesised) | 0 | none |
| `door_unlock`, `door_buy`, `door_open` | the plank door (`door_side`), at the buyer and at the slab | existing (`door_buy` is ElevenLabs, free tier, already licensed in `eleven/LICENSE.md`) | 0 | none |
| `debris_clear` | the debris blocker on a stair (`door_stairs_start`, `door_stairs_side`) coming off: planks, a table dragged, rubble | synthesised (new, 3 takes of about 2 s) | 0 | **300** (3 takes of 2.5 s) |
| `step_wood`, `step_own_wood` | feet on the stairs and the upper floor | synthesised (new, 8 takes each) | 0 | none |
| the dead's voices outside | the dead rise 6 to 7 m outside the windows and groan as they always do | existing (`zombie_*`), placed by the zombies | 0 | none |
| voice lines | none: the map has no characters, the soldiers' lines fit it, the chalk messages are written | existing | 0 | none |

**Spent now: 0 credits.** **Waits on a decision to generate (optional): 540 credits** (`debris_clear` 300 and
`yard_rattle` 240), which leaves 960 of the 1,500 for #252. If the maintainer does not generate them, the
synthesised files stay: the plan that made each file is in its row, and a generated file would add its prompt and the plan
to `eleven/LICENSE.md` (#252).

## Where the sounds are placed

`SmallMapSounds` (`game/gameplay/night/smallmap_sounds.gd`) is the second map's `NightSounds`: a node that listens to the
client state's events like it and reads the places off the greybox and the backdrop. It starts nothing until the map
is in a night (the map picker, #624, adds it where `NightSounds` is added).

Measurements and the capture are added below as they are made.
