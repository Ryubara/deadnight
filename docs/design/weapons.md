# Weapons

How a shot works, what it costs a zombie and what each weapon is for. The code is `game/gameplay/weapons/`; every
number is in one `.tres` per weapon (`defs/`), and the tests pin the behaviour (`game/tests/weapons/`). The economy it
feeds is in [Rounds, points and fuel](rounds.md); how it was built is in [Weapon firing](../research/weapon-firing.md).

## Built for a server

The server decides every hit. The client shows the shot at once and the server's events correct it.

- **Client, at once:** muzzle flash, small impacts (dust on a wall, red on a zombie), a light view shake for the
  shooter, and the sound request, drawn from the shooter's own view with
  the same `AimResolver` code the server runs, and the same spread (the pellet pattern comes from a seed of the match,
  the shooter and the shot number, so both sides scatter alike).
- **Server, on arrival:** the `fire` action is checked (cooldown, magazine, reload), then judged against the targets as
  the shooter saw them (the **rewind**), and the damage is dealt. `damage_dealt`, `target_killed` and the rules' own
  events go back to everyone.
- **Plain data both ways.** An action is a dictionary (`CombatAction.fire(...)`: camera ray, muzzle, shot number, the
  server time the shooter was viewing). An answer is a list of dictionaries. Nothing needs a node or a peer, so the
  transport chosen in #38 changes only the thin link that carries them (`LoopbackLink` stands in, and single-player
  keeps using it).
- **Rewind, capped.** The server keeps a short history of where every zombie stood each step and judges a shot at the
  shooter's view time, never further back than **0.25 s**. A laggy client leads its targets past that; a lying client
  gains nothing beyond a quarter second.
- **Projectiles are not rewound.** They fly in the present, stepped on the server's fixed step; clients draw a copy that
  follows the same code and end it on the server's `projectile_burst`.
- **The server owns the muzzle.** A fire command's muzzle is never read: the night server places it on the body it
  holds (`muzzle_offset`, turned to the body's facing), and the aim origin is pulled back to within `origin_slack`
  (3 m) of the head (`test_night_shot_authority`).

## Hitscan and projectile weapons

`WeaponDef.kind` says how a weapon's shot travels, and the look follows from it (`ShotEffects.shot`):

- **`HITSCAN`** (revolver, Tommy gun, shotgun, rifle): the shot lands the instant the trigger is pulled. The
  player sees a muzzle flash on the weapon, then a small spark, puff and mark where it ended on something (when it
  ended short of its range) or a small red puff on a zombie, and no bullet and no streak ([Shot
  feedback](shot-feedback.md), [Camera shake](camera-shake.md)). A weapon may set `WeaponDef.tracer` (off by default) to
  draw a streak from the muzzle to each end, for a future beam-like hitscan weapon; none of the shipped weapons does.
- **`PROJECTILE`** (the flare gun): a body that flies on the server's fixed step and bursts (`projectile_spawned`,
  `projectile_burst`); the shot itself draws only the muzzle flash. **Future launchers and ray guns use `PROJECTILE`**,
  so a travelling shot is always a real body with its own flight, not a drawn line. In the night `NightView` draws
  each one as a `ProjectileView` (a hot core, a flickering halo and a short spark trail), flown with the server's
  `ProjectileState` against the walls and ended by the burst (a spark and a flash). It makes no light: the lot's light
  cap leaves room for a flash and a blast only (`test_lot_light_cap`).
- **`MELEE`** (crowbar, baseball bat, fire axe): a sweep from the player's head (not the shoulder camera), a swing on
  the Soldier, a spark on a hit; no muzzle flash, no streak, no impact puff.

## The roster

Every model in `game/assets/weapons/` and what became of it. A weapon is a **definition** (`defs/<id>.tres`) with a
**source**: the **start**, a **wall** buy or the prize **crane**. `WeaponCatalog.IDS` lists them and
`game/tests/night/test_every_weapon.gd` fails when a definition has no source, when the crane's pool is not drawn
whole by seeded plays, or when a weapon a source gives does not reach the hand (taken, equipped, swung or fired with
the real command, its own model drawn).

| Model (`assets/weapons/`) | Definition | How it is obtained | Per hit / interval |
| --- | --- | --- | --- |
| `revolver` | `pistol`, the Revolver | **Start** (in hand) | 24 / 0.28 s |
| `crowbar` | `crowbar` | **Start** (carried, never dry) | 45 / 0.55 s |
| `double_shotgun` | `shotgun`, the Pump shotgun | **Wall** 900, and the **crane** (weight 4) | 19 x 8 / 0.8 s |
| `lever_rifle` | `rifle`, the Hunting rifle | **Wall** 1,200, and the **crane** (3) | 95 / 0.5 s |
| `tommy_gun` | `smg`, the Tommy gun | **Crane** only (2) | 14 / 0.075 s |
| `flare_gun` | `flare_gun` | **Crane** only (1); becomes a lure (#439) | 90 + blast 60 / 0.8 s |
| `baseball_bat` | `baseball_bat` | **Crane** only (0.5) | 60 / 0.4 s, sweeps 4 |
| `fire_axe` | `fire_axe` | **Crane** only (0.5) | 150 / 0.9 s, head x2.5 |
| `hammer` | none | A tool: the repair clip's prop, not a weapon (see below) | |
| `grenade` | none (`frag.tres` is its own system) | Thrown, not a crane prize: the start (2) and the shop's grenades | 150 blast |

**The crane gives every weapon the start and the wall do not**, the revolver and the crowbar excepted (the buyer
owns them from the first second, and the crane never gives a weapon the buyer has). A buyer who has every prize of the
pool gets "already owned" and no play. The pool and its weights are the shop item `crane_play`; the odds are
[the mystery box page](../research/mystery-box.md).

**The bat and the axe** were models with no definition. They are melee weapons held as `Melee` (the Swing clip, no
flash, a spark on a hit) with their own hold files, so each shows its own model. They are **found only in the prize
crane, never at the start**, and a player carries two weapons with no separate melee slot ([#410](https://github.com/Ryubara/deadnight/issues/410)),
so one in hand takes a slot a firearm could have had. That is why they are cut stronger than the crowbar (82 a second)
and than the revolver (86): the bat is the crowd weapon (a quick blow that kills a round-1 walker, a sweep that hits
four, 150 a second), the axe is the heavy one (one blow kills a walker of any round up to 10, a head blow x2.5, the
slowest, 167 a second). Neither needs ammunition, which is what the slot buys, against a firearm's 190 a second that
runs dry. They are not re-cut at the projector (the re-cut list is the firearms).

**Decided by the maintainer** (on #461, recorded on #410 and #411):

- The hammer is a cosmetic repair tool only: no definition, no slot.
- No grenades from the crane: the grenade is thrown by its own system.
- Carry ([#410](https://github.com/Ryubara/deadnight/issues/410)): a third weapon replaces the one in hand; the
  replaced weapon is disposed of and **goes back into the weapon pool**, not dropped. This branch does not do the
  carry; when it lands, the crane's pool and its "already owned" rule follow it (the revolver and the crowbar would
  join the pool the moment a player can lose one).
- Quick melee on `V` ([#411](https://github.com/Ryubara/deadnight/issues/411)) is the always-available knife blow with
  whatever is in hand, so no melee weapon is needed in a slot for emergencies.

## The shoulder camera

The camera sits behind and to the right of the player, so the crosshair and the barrel do not line up. A shot is
resolved in two steps: a ray from the camera finds what the crosshair is on (the world or a zombie, ignoring anything
between the camera and the shooter), then the shot leaves the **muzzle toward that point**. If a corner stands between
the muzzle and the point, the muzzle ray hits the corner: the shoulder camera cannot shoot around it. Stepping out
beside the corner makes the same shot land (both are tested and in the capture).

## Hit zones

Zombies are shot at through their zones, not their meshes: a head sphere, a body capsule and four limb capsules
(`Hitbox`); the headliner has a fifth, `weak`, a ball on its lit lamp that no other zombie has (the weapons list no
multiplier for it: the rules' x2.2 is the one). The test range draws them as they are. The whole set is sized to the
zombie: a brute's zones are 1.18 times a walker's, a crawler's 0.6 (its look's height times its type's `hit_chance`).

| Zone | Pistol | SMG | Shotgun (per pellet) | Rifle | Flare gun | Crowbar | Bat | Axe |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Head | x2.5 | x2.0 | x1.5 | x2.5 | x1.5 | x1.5 | x1.5 | x2.5 |
| Body | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 |
| Limb | x0.6 | x0.6 | x0.6 | x0.7 | x0.6 | x0.75 | x0.75 | x0.7 |

Damage of one hit is `damage x falloff(distance) x zone x 0.6^(bodies already passed)`. A shot that lands on one
zombie with several pellets is one hit for the rules (one `hit` action carrying the damage, headshot
if any pellet struck the head), so a shotgun cannot farm the four-point hit payout.

## The arsenal

Numbers as shipped. "Per hit" is the body zone at point blank; falloff slides linearly from the start to the end
distance down to the floor and holds there to the range.

| Weapon | Kind | Per hit | Interval | Magazine / reserve | Reload | Falloff start to end (floor) | Range |
| --- | --- | ---: | ---: | --- | ---: | --- | ---: |
| Revolver | hitscan, semi | 24 | 0.28 s | 10 / 40 (max 80) | 1.3 s | 12 to 35 m (55%) | 60 m |
| Tommy gun | hitscan, auto | 14 | 0.075 s | 30 / 120 (max 180) | 1.9 s | 10 to 30 m (50%) | 50 m |
| Pump shotgun | 8 pellets, 5 degrees | 19 x 8 | 0.8 s | 6 / 30 (max 60) | 2.4 s | 8 to 22 m (35%) | 30 m |
| Hunting rifle | hitscan, pierces 2 | 95 | 0.5 s | 8 / 40 (max 80) | 2.2 s | 40 to 90 m (80%) | 120 m |
| Flare gun | projectile, lobbed | 90 + blast 60 (3 m) | 0.8 s | 1 / 6 (max 12) | 2.0 s | none | 40 m |
| Crowbar | melee sweep, 2 targets | 45 | 0.55 s | none | none | none | 1.9 m |
| Baseball bat | melee sweep, 4 targets | 60 | 0.4 s | none | none | none | 1.8 m |
| Fire axe | melee sweep, 2 targets | 150 | 0.9 s | none | none | none | 1.8 m |

Shots to kill at close range (head / body), against the health in [the rounds table](rounds.md#the-tuning-table):

| Weapon | Round 1 (50) | Round 5 (82) | Round 10 (121) | Damage a second (body) | With reloads |
| --- | --- | --- | --- | ---: | ---: |
| Revolver | 1 / 3 | 2 / 4 | 3 / 6 | 86 | 59 |
| Tommy gun | 2 / 4 | 3 / 6 | 5 / 9 | 187 | 101 |
| Pump shotgun | 1 / 1 | 1 / 1 | 1 / 1 | 190 | 127 |
| Hunting rifle | 1 / 1 | 1 / 1 | 1 / 2 | 190 | 123 |
| Flare gun | 1 / 1 | 1 / 1 | 2 / 2 | 112 + blast | 32 + blast |
| Crowbar | 1 / 2 | 1 / 2 | 2 / 3 | 82 | 82 |
| Baseball bat | 1 / 1 | 1 / 2 | 2 / 3 | 150 | 150 |
| Fire axe | 1 / 1 | 1 / 1 | 1 / 1 | 167 | 167 |

The shots are the health of the zombie (the table in the page above; `rounds.md` is the source) over the weapon's
damage, rounded up. "With reloads" is the sustained rate over a whole magazine and its reload, the number the
[balance simulator](rounds.md#the-balance-simulator) picks weapons by.

## Why these numbers

- **The starter is a revolver with a one-shot headshot.** At 24 damage and x2.5 on the head, a round-1 zombie (50)
  falls to one headshot or three body shots, so aiming pays from the first minute; by round 5 (82) it takes two
  headshots or four body shots and by round 10 (121) six body shots. The health curve was lowered to the weapons
  that exist (rounds.md, the balance simulator): the shop weapons were stepped up in #265 (rifle 95,
  shotgun 19 a pellet) so that buying one is worth rounds.
- **A weapon can be re-cut once** at the projector: x1.75 damage, x1.5 magazine and reserve limit, filled, for 1,500
  points ([the re-cut](upgrades.md)). The table above is the weapon as shipped; a re-cut one has its damage in the
  column multiplied and its magazine and reserve limit grown, and kills in fewer shots (a re-cut revolver, 42 a hit,
  kills a round-10 zombie in 3 body shots). This is what lets the health curve climb faster than the shipped weapons
  could follow.
- **Each weapon has one job.** The SMG is volume at short range (the most damage a second, a short magazine of
  patience before the reload); the shotgun is a close wall; the rifle is the precision and the line (it passes through
  two zombies, each blow 40% weaker, which rewards lining the dead up); the flare gun is crowd control with a risk of
  being too close (the blast hurts anyone near the point of impact, the shooter's own party excluded for now); the
  crowbar never runs dry and pays the melee kill bonus (130 points) for the risk of being in reach.
- **The shotgun cannot farm points.** Pellets add up to one hit for the rules, and its damage falls to 35% by 22
  m, so it is a close weapon by its own numbers, not by a rule.
- **Ammo is the other economy.** Reserves are small on purpose (a round-10 zombie is 5 revolver body shots), so
  headshots and melee are worth more than the points they pay. Ammunition is sold ([Rounds](rounds.md#ammunition));
  the weapon carry limit is not decided here; see the open questions.

## Grenades

Hold the throw button to cook, let go to throw; the second button tosses underarm. Code in
`game/gameplay/grenades/`, numbers in `defs/frag.tres` (the pineapple) and the rules' `ExplosiveTuning`; the tests are
in `game/tests/grenades/`. How it was built: [Grenades](../research/grenades.md).

**Server first.** The pin and the throw are two actions (`cook`, `throw`) that a `GrenadeThrower` makes from the
`throw_over` and `throw_under` levels of each `PlayerCommand`, so a replay of the commands replays the cook and the
throw. The server owns the fuse and the flight (`GrenadeState`, stepped on the fixed tick: gravity, bounce, roll,
rest); the client draws its own copy the moment the button is released and the server's `grenade_thrown` corrects it.
The same stepping gives the arc preview, so the preview, the prediction and the server land on one point.

**The server believes itself.** The host tells the server where every player stands; a grenade leaves from 1.45 m above
those feet, and the hand the client reports is kept only within 1 m of that point (a hand claimed further out is pulled
in, so lag does not refuse a real throw). The client's own speed adds at most 7.5 m/s, the sprint with a little slack. A
hand or velocity that is not a finite number is refused (`bad_hand`, `bad_velocity`) and a cook that was refused costs no
grenade. A grenade held while walking goes with the player, so one that goes off in the hand goes off where they are.
Which zombies a blast can hit is the rules' answer, never a list the server keeps.

**Down with the pin out.** A player who is downed (or leaves) while cooking **drops the grenade at their feet and its
fuse keeps running**: it is spent, it is not given back, and it hurts whoever is near, the downed player included (40%),
which makes a revive during a cook a risk the team can see. The throw that follows is refused (`player_downed`); a
revived player starts again with a fresh pin.

**In the night.** The server throws for every player on their command's grenade buttons (G, the right shoulder
button and the touch Grenade button for the overarm throw; H and the left shoulder button for the toss), only while a
round is on and the player is up and has one. The count drops at the pin, so a grenade cooked to the end and let go
in the hand is spent and costs the thrower 40% of the blast. The Soldier cooks and throws with his own clips. Wired
and proven in #351: [Grenades research](../research/grenades.md#in-the-night-351).

| Thing | Number |
| --- | --- |
| Fuse | 3.0 s from the pin; cooking spends it in the hand; held to the end it goes off in the hand |
| Overarm | 15 m/s, lifted 8 degrees; keeps half of the thrower's speed |
| Underarm | 7 m/s, lifted 22 degrees; it rolls |
| Flight | gravity 16 m/s2; floor bounce keeps 42%, wall bounce 50%, 20% lost along the surface; under 1.4 m/s it rolls, 3.5 m/s2 of friction, stops under 0.2 m/s |
| Blast | 150 at the centre and out to 2 m, sliding to 0 at 8 m |
| Cover | a line from the blast (0.25 m up) to each of the six hit parts; a part with something solid in the way takes nothing |
| Shares of the blast | legs 25% each, body 25%, arms 10% each, head 5% (a blast goes off low) |
| Knockback, stun | up to 7 m/s along the ground and 3 m/s up, 1.6 s stun, both falling off like the damage |
| Thrower | takes 40% of what a zombie would at that spot, cover included; other players take nothing (a server flag turns friendly fire on) |
| Authority | hand within 1 m of 1.45 m above the server's feet; client speed at most 7.5 m/s; a dropped grenade starts 0.3 m above the feet |
| Carry | start with 2, every round start tops up to 3, at most 5; the shop sells 2 for 150 (+5 a round) |
| Kill points | 40 for a zombie the blast kills (a hit that does not kill pays the usual 4) |

A grenade is a sure kill only early: at 150 it kills a round-1 zombie (50) out to 6.0 m and a round-5 one (82) out to
4.7 m; from round 12 (139) only near the centre of the blast, and no round-14 one (159) at all (the climb is 7% a round).

**Crippling.** The rules (`explosion` action) decide, never the world. A zombie that survives loses its legs and
becomes a crawler (once; one `zombie_crippled` event, speed times 0.35) when either:

- the blast damage on its **legs** adds up to a quarter of its full health (the blast was low and close), or
- the blast leaves it with **5% to 40%** of its health and a seeded roll (60%) says so: hurt badly but not dead.

So the ring just outside the kill radius makes crawlers, and in late rounds a grenade cripples everything near it
instead of killing it. The roll has its own stream in the rules' seed and is drawn only for a zombie in the band, so
every machine agrees. Gibs, decals and the fireball are client only and decide nothing.

## Open questions

- **Shop weapons: stepped up (#254, #265).** The rifle (95, 0.5 s) and the shotgun (19 a pellet, 0.8 s) are applied;
  the reasoning and the reference are in [round scaling](../research/round-scaling.md). What is still missing is a
  way for a weapon to keep pace with health that compounds (the original's Pack-a-Punch): an issue.
- **The carry limit: proposed, awaiting the maintainer (#410).** Two guns and the melee weapon; buying or taking a
  third gun replaces the one in hand and its reserve. Today a player may carry every weapon, and the swap button (F,
  d-pad up) takes the next one carried in hand.
- **The flare: decided, no damage; it becomes a lure (#439).** The maintainer: it acts like a monkey bomb or a pipe
  bomb, no damage for now. Zombies in a radius turn to it for a set time. Until #439 lands the table's flare numbers
  (a hit and a blast) are the old design. A grenade still hurts the thrower alone (`player_blasted`).
- **Reload as a skill.** A magazine swap that rewards a timed second press, and cancelling a reload by sprinting, wait
  for the controller (#14).
- **Quick melee: not built (#411).** On its own button, with the crowbar-style sweep and a fixed short cooldown; the
  sweep and its damage exist, the button, the command bit and the clip do not.
