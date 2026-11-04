# Hit zones follow the bodies

Shots at zombies are tested against analytic zones (`Hitbox`, `HitShapes`: spheres and capsules), never the mesh, so
the server can rewind any zombie ([weapons](weapons.md)). The maintainer's report (#694: "Bullets landing on Zombie
crawlers is a bit hit or miss especially when hitting their forehead") found that the zones did not follow the bodies.

## What was wrong

- **One standing set for every pose.** Every zombie had the same six shapes, placed upright from its feet: a head
  sphere 1.62 m up and four thin limbs. A crawler got the set scaled by 0.6, so its head zone floated 0.97 m above the
  ground, behind the head, while the body lies on all fours with a chibi head half a metre across at 0.5 m, ahead of
  its feet. Of the shots that touched a crawler's mesh, 22% registered; of those at the forehead, none counted as a
  headshot.
- **The walkers were wrong too**, only less visibly: 56 to 70% of the shots that touched a walker registered, and 4 to
  27% of those at its head counted as head, because the head is a third of the figure and the zone was a 0.22 m ball.
- **The poses were never asked.** The view plays the crawl, punch, hit reaction and tear clips by mode; the server
  knew only a position and a yaw. Nothing compared the zones with the mesh the player sees: `test_hit_zones.gd` fired
  rays at the zones themselves, and the aim tests aimed at a point computed from the same numbers.
- Not the cause: no zone was under the ground (the floor's ray is judged past the zombie), and the lag compensator
  rewound the position and yaw as sent (it only kept the size, not a pose, because there was none to keep).

## What it does now

| Piece | Where |
| --- | --- |
| Skins the near mesh on the CPU in any clip at any time, and tells which part (head, torso, arm, leg) a ray touches | `ZombieMeshProbe` (tests) |
| Fires a grid of parallel rays from 8 sides and 2 to 3 heights at it and counts what a shooter registers | `ZombieRayGrid` (tests) |
| Fits the zones: per look and pose, the bone pieces over 32 moments of each clip, the moments of a piece clustered into several spheres and capsules (an envelope of its travel, the server not knowing the clip's phase) | `tools/hit_fit/fit_hit_shapes.gd` writes `HitPoseData` |
| Which set a zombie is shot at: its look and the pose its mode and speed put it in (`move`, `run`, `sprint`, `strike`, `stagger`, `tear`, `roar`, `climb`) | `ZombiePose`, `ZombieBody.hit_target` |
| Prints the before and after table | `tools/hit_fit/hit_rates.gd` |

The set travels with the target (`"pose"`, kept by the lag compensator and sent by `NightServer`), and a crawler's
`hit_chance` (0.6) no longer shrinks its zones a second time: they are its body on the ground. A run and a sprint have
sets of their own because the head dives forward and down in them: one set over every gait made the head zone swallow
the chest.

Two rules of the ray: a limb the ray meets first gives way to a body or head zone within 0.2 m behind it (an arm
swinging in front of the chest is cover, not the part aimed at), and the boss's lamp counts when reached within 0.45 m
behind the first surface (its jaw hangs over the lens from the front).

A climb over a sill has a set of its own with twice the shapes of a piece (`CLIMB_PARTS`): the clip moves the body over
a metre round its origin, which the simulation holds at the sill's height, and the walker's upright set put the head
zone 0.9 m over the head the player sees. Bots and the autopilot aim at the middle of that set, not at the upright
1.1 m. At five moments of each clip a walker and a crawler register 94% or more of the shots that touch the mesh; 65%
or more of head shots count as head (69% on the way up, when the hands are in front of the face) (#991).

## Numbers

Shots that touch the visible mesh, through the weapons' trace, over the poses in the table
(`tools/hit_fit/hit_rates.gd`, 8 sides, 0 and 25 degrees above the horizon, 8 cm grid). The "as head" columns are the
share of shots at the head's triangles that count as a headshot.

| Body, clip | Registered before | after | As head before | after | Off the mesh before | after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| crawler, Crawl | 21.8% | 99.5% | 1.1% | 77.9% | 48.2% | 43.2% |
| crawler, Punch | 26.8% | 96.9% | 1.4% | 93.1% | 21.9% | 55.2% |
| walker, Idle | 70.2% | 98.8% | 24.7% | 91.2% | 17.0% | 36.5% |
| walker, Walk | 65.5% | 98.3% | 24.4% | 94.2% | 24.8% | 38.2% |
| walker, Run | 56.4% | 98.1% | 4.1% | 87.4% | 33.1% | 47.7% |
| walker, Punch | 70.3% | 97.1% | 26.7% | 94.3% | 17.8% | 51.7% |
| walker, HitReact | 66.2% | 97.7% | 14.9% | 97.9% | 21.7% | 30.4% |
| brute, Walk | 66.6% | 99.1% | 26.0% | 95.2% | 17.8% | 34.6% |
| headliner, Boss_Walk | 55.2% | 94.1% | 11.6% | 80.7% | 9.3% | 26.7% |

Forehead shots at a crawler through a whole combat server, in four moments of its crawl: 7 of 12 did damage before and
none was a headshot; 12 of 12 do now, all headshots.

The last two columns are what a fit costs: of the shots the zones register, 27 to 55% miss the visible mesh (before: 9 to
48%). That is the envelope of the motion and the fat limbs (fingers, swing); a capsule fitted to one frame still leaves
24%. The head of a head-on crawl counts as head 78% of the time: its reaching hands are in front of the face and the
limb zone is nearer than the head's.

## Changing a model or a clip

Re-run `godot --headless --path game -s res://tools/hit_fit/fit_hit_shapes.gd` and commit `hit_pose_data.gd`;
`--check` prints the grid for each set instead of writing it. `test_hit_zones_follow_bodies.gd` fails when the zones
and the mesh come apart.

## Not done, and what it moves

- **Headshots are common now, and the game is balanced around that (#745).** The head is half the figure and its zone
  now is too: the bots, aimed at the chest, land 64 to 88% of their hits on the head (the bands test,
  `test_bot_bands.gd`; 6 to 30% from the old 0.22 m ball). `SimSkill`'s head rate and dodge were set to those readings
  and the game retuned around them (the headshot kill pays 70, health climbs 15% a round after round 8, the brute has
  3 times a walker's health; [the numbers](balance-simulator.md#the-headshot-retune-745)). The zones were **not**
  changed. **Open for the maintainer: keep a head this big, or shrink the head zone?** The measured cost of keeping it
  is that a shot no longer chooses between head and body (about 90% of kills are headshots at every skill level, the
  `x2.5` bonus is a flat damage bonus and "aiming pays" of [weapons](../design/weapons.md#why-these-numbers) is
  weaker), and the retune had to take points and late health to hold the gate's ranges. A smaller zone (the skull, not the
  whole chibi head) would give the bonus back to aim; the multipliers, pay and health could then go back toward their
  old values, and `SimSkill`'s head rates would be measured again.
- Grenade blasts still weigh the six standing shapes (`Hitbox.STANDING`, `BlastModel`).
- The bots and the touch aim assist still aim at the old upright points (a crawler's low, `ZombieModels.aim_scale`);
  the touch assist's own test measures its thumb bot on the standing set the simulator's numbers came from.
- A rising zombie (`EMERGING`, buried under the ground) is still shot where it stands, as before.
