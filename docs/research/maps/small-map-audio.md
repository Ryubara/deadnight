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
client state's events like it and reads the places off the greybox and the backdrop (`setup(state, greybox, backdrop)`,
called with both in the tree). The guns, the dead, the till and the feet stay the night's. Its parts:

| Part | What it does |
| --- | --- |
| `SmallMapRooms` | reads each room's rectangle and floor height off the greybox (`Start`, `Side`, `UpperA`, `UpperB`) and says which room a point is in (a stair belongs to the room below until its top; outside the walls is no room) |
| room tone, roof wind | `bed_room_tone` and `bed_roof_wind` are flat beds whose level follows the listener's room (`SmallMapSoundTuning.tone_db`, `roof_db`) through `Audio.set_bed_level`, at the beds' fade rates; outside the walls the tone fades away. The roof wind (and the yard's wind loops, below) also swells with the gust that is blowing, up to 3 dB (6 dB for the yard) at its peak: `SmallMapSounds.wind` is the night's `WindSounds`, read ten times a second (#809, [the wind](../wind.md#the-gust-drives-the-loops-809)); the roof wind's trim is 3 dB higher than the table below says (the report takes it off) and every room rests 3 dB lower, so what is heard at rest is unchanged |
| `SmallMapWays` | how a sound outside reaches a listener inside: from the window of the listener's room that gives the shortest way round, at the level of the whole way and the window's state (boards left: boarded -8 dB, none or a breach: open -1.5 dB), or through the wall (-15 dB, dull); fences and the ground are not walls |
| `SmallMapYard` | nine 3D loops at the backdrop's places: wind in the four corners of the yard (each starting at its own offset and pitch), the two fires, the hum on the two poles nearest the building (20 m apart), the drive-in's road; each is played from the window it comes in at and stops out of reach |
| rattles | every 12 to 25 s a fence rattles at a wire-fence run or post within 60 m, through the same ways, from a seeded generator |
| pieces | `board_torn` and `board_repaired` play `board_tear`, `board_last` and `board_repair` at the window's opening (and tell the ways how many boards are left); `door_opened` plays `door_open` at the plank door and `debris_clear` at a debris blocker, where the slab stood (read at setup, because a bought door's slabs are taken away) |
| feet | `FootSurface` knows `wood`: the stairs and the upper floor carry `surface = "wood"` (the greybox generator writes it), so `FootstepSounds` plays `step_wood` and `step_own_wood` there and the asphalt files on the ground floor |

Wiring left to the map picker (#624), which adds `SmallMapSounds` where it adds `NightSounds`:

- Give it the night's wind: `small_map_sounds.wind = night_sounds.wind` (`NightSounds` makes the `WindSounds`, with or without
  the lot's crickets and highway); without it the roof and yard wind rest where they did before #809.

- Start the map's sounds **in place of** the lot's crickets and highway (`NightSounds.NIGHT_BEDS`): the yard is frosted
  and still, nothing sings. The bed pool holds six: the room tone, the roof wind, the score and the tension are four.
- Give `WorldSounds.item_sounds` the map's `SmallMapSounds.ITEM_SOUNDS`: a bought debris blocker plays only the till; the
  pile's sound is its coming off, at the pile.
- `Audio.occluder_mask` stays the night's; the yard does its own routing and is not occluded twice.

## Levels

Measured by `tools/audio/smallmap_levels.py table` (the bank, the files, the engine's fall-off `unit_size / distance`).
Levels are RMS dBFS; the audible floor is -48 (12 dB under the room tone); the other beds are set beside the new ones.
Yard sounds are measured at window 1 with the listener 4.65 m inside it and each source as far beyond it as it stands in
the backdrop.

```text
sound            file rms   trim at unit  unit  reach  carry  boarded   open   wall
bed_room_tone       -14.9  -21.0   -35.9   8.0     50     32
bed_roof_wind       -19.0  -19.0   -38.0   8.0     50     25
yard_wind           -19.6  -10.5   -30.1  10.0     90     78    -48.9  -42.4  -55.9
yard_fire           -16.6  -10.5   -27.1  12.0    100    100    -49.0  -42.5  -56.0
yard_wire           -13.3  -17.5   -30.8  10.0     90     73    -51.8  -45.3  -58.8
yard_road           -17.6  -18.0   -35.6  40.0    170    167    -51.9  -45.4  -58.9
yard_rattle         -37.8   -8.5   -46.3   8.0     70     10    -65.7  -59.2  -72.7
debris_clear        -25.1    0.0   -25.1  10.0     60     60
step_wood           -23.2   -2.0   -25.2   4.0     30     30
step_own_wood       -20.7  -14.0   -34.7   8.0     30     30
bed_crickets        -27.4  -26.0   -53.4   8.0     50      4   (existing; cut again in #781)
bed_highway         -17.6  -18.0   -35.6   8.0     50     33   (existing)
bed_projector       -17.6  -14.0   -31.6   4.0     35     27   (existing)
board_tear          -26.7    2.0   -24.7   9.0     70     70   (existing)
door_open           -22.2   -2.0   -24.2  10.0     60     60   (existing)
step_own_asphalt    -20.6  -14.0   -34.6   8.0     30     30   (existing)
step_asphalt        -19.8   -2.0   -21.8   4.0     30     30   (existing)
```

- **The room tone sits with the other beds** (-35.9, the highway's -35.6; the crickets are -44), under a footstep
  (-34.7 for the player's own on wood, a step's peak much higher). The roof wind is 2 dB under it and, since #809,
  swells with the gust that is blowing (the table reads its rest level: its trim is 3 dB higher in the bank, and
  `smallmap_levels.py` takes that off).
- **Through a boarded window the yard is at the audible floor** (-49 to -52): heard, not noticed. With the boards torn
  off it is 6.5 dB up (-42 to -45), so a breach is audible in the room before it is seen; through a wall it is 7 dB
  under the floor. The rattle is a short peak, not a level: its peak at a boarded window is about -34 dBFS.
- **How far each carries in open air** before it falls to the floor: the fire to its reach (100 m), the road 167 m of
  its 170, the wind 78 m, a pole's hum 73 m, a rattle 10 m (a peak: heard to its 70 m reach at a window). A
  `debris_clear` and a board are at the level of a door (-25 dBFS) and carry the effects' 60 to 70 m.

A walk through the map (`game/tests/captures/audio_smallmap_tour.tscn`: a Movie Maker capture of the player's camera, a
teammate's feet and the events the server would send; every sound is played by `SmallMapSounds` or `FootstepSounds`),
then `smallmap_levels.py capture`: the mix's level in each stage, RMS dBFS.

| Stage | RMS | Peak | What plays |
| --- | ---: | ---: | --- |
| the hall: room tone, the yard behind boarded windows | -37.2 | -21.5 | tone, yard loops, steps |
| at a boarded window | -36.0 | -26.1 | the same, the yard from the window |
| the boards come off | -32.9 | -10.1 | `board_tear` twice, `board_last`, a rattle |
| the window is open | -35.7 | -12.0 | the yard through the open window, `board_repair` twice |
| the plank door | -34.4 | -13.6 | steps, `door_open` |
| the rewind room | -35.4 | -19.2 | tone, steps |
| the debris blocker comes off | -36.9 | -25.1 | `debris_clear` |
| up the stair on wood | -36.7 | -16.3 | `step_wood` |
| upstairs under the roof | -35.5 | -21.6 | tone and the roof wind, `step_wood` |
| a north window onto the yard | -37.1 | -24.5 | the yard through a boarded north window |
| the night is over | -93.6 | -69.8 | silence: the beds and the yard are gone |

Every stage sits between -32.9 and -37.2 dBFS, so no sound jumps out of the mix, and the peaks are the pieces (a board
cracking at -10 dBFS, the loudest) over the beds' -35. A first run had the window stage at -26.9: the router assumed the
wrong fall-off, and the loops at a window were 18 dB up (kit lesson
`docs/lessons/2026-11-03-a-routed-yard-sound-used-the-wrong-fall-off.md`).

## Tests

`test_smallmap_sounds.gd` (the catalog and its files, no padlock on a debris purchase, the rooms, the tone and the roof
wind following the room, the end of the night, boards, doors, debris, feet on wood), `test_smallmap_yard.gd` (the loops
at the backdrop's places, boarded and open windows, the wall, outside, a window nearer the listener is not louder, a
loop's level moving at the slew rate, reach, the rattles: where, when, never out of reach, the same for a seed),
`test_audio_beds.gd` (`set_bed_level`) and `test_world_sounds.gd` (`item_sounds`). The headless test reads the
backdrop's copies from the multimesh `buffer`: `get_instance_transform` reads zero without a renderer.

## What waits on generation

Nothing blocks shipping: every sound above is synthesised, so no ElevenLabs credit was spent and no licence entry is
added. If the maintainer judges the synthesised `debris_clear` or `yard_rattle` short of the real thing, generating them
costs 300 and 240 credits (540 of the 1,500), and the decision on the plan's commercial rights (#252) comes first. How
the synthesised versions sound to a listener is the maintainer's judgement: this page has levels and spectra, not ears.
