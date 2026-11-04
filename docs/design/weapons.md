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
  draw a streak from the muzzle to each end, for a beam-like hitscan weapon: only the freeze gun does, in its own
  icy colour (`bolt_core_colour`).
- **`PROJECTILE`** (the flare gun, the ray gun): a body that flies on the server's fixed step and bursts (`projectile_spawned`,
  `projectile_burst`); the shot itself draws only the muzzle flash. **Future launchers and ray guns use `PROJECTILE`**,
  so a travelling shot is always a real body with its own flight, not a drawn line. In the night `NightView` draws
  each one as a `ProjectileView` (a hot core, a flickering halo and a short spark trail), flown with the server's
  `ProjectileState` against the walls and ended by the burst (a spark and a flash). It makes no light: the lot's light
  cap leaves room for a flash and a blast only (`test_lot_light_cap`).
- **`MELEE`** (crowbar, baseball bat, fire axe): a sweep from the player's head (not the shoulder camera), a swing on
  the Soldier, a spark on a hit; no muzzle flash, no streak, no impact puff. The quick melee ([below](#quick-melee))
  is the same sweep with its own definition, on its own button.

## The roster

Every model in `game/assets/weapons/` and what became of it. A weapon is a **definition** (`defs/<id>.tres`) with a
**source**: the **start**, a **wall** buy or the prize **crane**. `WeaponCatalog.IDS` lists them and
`game/tests/night/test_every_weapon.gd` fails when a definition has no source, when the crane's pool is not drawn
whole by seeded plays, or when a weapon a source gives does not reach the hand (taken, equipped, swung or fired with
the real command, its own model drawn).

| Model (`assets/weapons/`) | Definition | How it is obtained | Per hit / interval |
| --- | --- | --- | --- |
| `revolver` | `pistol`, the Revolver | **Start** (in hand) | 24 / 0.28 s |
| `crowbar` | `crowbar` | The **crane** only (1); no longer a start weapon, the quick melee replaced it | 55 / 0.55 s, every zone |
| `double_shotgun` | `shotgun`, the Double-barrel | **Wall** 900, and the **crane** (weight 4) | 21 x 8 / 0.3 s |
| `lever_rifle` | `rifle`, the Hunting rifle | **Wall** 1,200, and the **crane** (3) | 95 / 0.5 s |
| `tommy_gun` | `smg`, the Tommy gun | **Crane** only (2) | 14 / 0.075 s |
| `flare_gun` | `flare_gun` | **Crane** only (1); becomes a lure (#439) | 90 + blast 60 / 0.8 s |
| `ray_gun` | `ray_gun`, the Moonbeam Pistol | **Crane** only (1.5); [wonder weapons](#wonder-weapons-and-status-effects) | 300 + blast 160 / 0.45 s |
| `freeze_gun` | `freeze_gun`, the Snow-Cone Gun | **Crane** only (1.5) | 30 + bloom freezes / 0.8 s |
| `baseball_bat` | `baseball_bat` | **Crane** only (0.5) | 60 / 0.4 s, sweeps 4, every zone |
| `fire_axe` | `fire_axe` | **Crane** only (0.5) | 150 / 0.9 s, every zone |
| `mp5` ([models](../research/weapon-models.md)) | `mp5`, the Usher SMG | **Crane** only (2) | 15 / 0.10 s |
| `ppsh` | `ppsh`, the Reel Gun | **Crane** only (2) | 10 / 0.055 s |
| `m4a1` | `m4a1`, the Matinee Carbine | **Crane** only (1.5) | 20 / 0.11 s |
| `m249` | `m249`, the Double-Feature Gun | **Crane** only (1.5) | 15 / 0.09 s, pierces 1 |
| `fifty_cal` | `fifty_cal`, the .50 calibre rifle | **Crane** only (1.5) | 220 / 0.9 s, pierces 4 |
| `pump_870` | `pump_870`, the Popper | **Crane** only (2) | 22 x 6 / 0.65 s |
| `service_pistol` twice (#797) | `dual_pistols`, the Dual Pistols | **Crane** only (2.5), on both maps | 17 / 0.15 s, a hand each shot |
| none: not a weapon | `quick_melee` (`QUICK_MELEE`, not in `IDS`) | Every player, on `V`; never carried, bought or won | 50 / 0.6 s, 1.6 m, every zone |
| `hammer` | none | A tool: the repair clip's prop, not a weapon (see below) | |
| `grenade` | none (`frag.tres` is its own system) | Thrown, not a crane prize: the start (2) and the shop's grenades | 150 blast |

**The six firearms of [#793](https://github.com/Ryubara/deadnight/issues/793)** (the MP5, PPSh, M4A1, M249, .50 calibre
rifle and Pump 870) are built: [their numbers](#the-nine-new-weapons-785) and [what is special about three of
them](#the-six-firearms-793). The dual pistols, ray gun and freeze gun are [#789](https://github.com/Ryubara/deadnight/issues/789)
and [#788](https://github.com/Ryubara/deadnight/issues/788).

**On the second map the walls sell more** ([the shop of the small map](smallmap.md#the-shop-formula-rows-22-to-25)):
nine places for eight weapons, so the revolver (90, back in the pool after it is given up), the crowbar (270), the
shotgun (540, on two walls), the Tommy gun (540), the bat (540), the flare gun (630), the axe (720) and, in the cabinet
upstairs, the rifle (675) are all bought by the wall there, at prices that climb from room to room, and its box
(425, one place) gives any weapon the buyer lacks. The tuning is the map's own overlay; the lot's walls are unchanged.

**The crane gives every weapon the start and the wall do not**, the revolver too once the buyer has given it up (they
carry it from the first second, and the crane never gives a weapon the buyer carries). A player carries two weapons, so
the pool is never empty for them. The pool and its weights are the shop item `crane_play`; the
odds are [the mystery box page](../research/mystery-box.md). `game/tests/rules/test_crane_pool.gd` fails when a weapon
of the catalogue is not in the pool (unless it is listed there as no prize, with the reason; none is) and when 10,000
first rolls, each from the seed a solo night takes, are not spread by the weights. A solo night draws a new seed each
time (`NightScreen.start_seed`, [#685](https://github.com/Ryubara/deadnight/issues/685)): with the old fixed one
every night rolled the shotgun first.

**The dual pistols** (#789) are two semi-automatic pistols, one in each hand, with the numbers of the roster plan
(#785, the nine new weapons). One fire button, held to keep firing: the shots **alternate**,
right hand first (`WeaponDef.dual`; the server numbers the shot's `hand`, 0 right and 1 left, and each client flashes and
kicks that gun). The two guns share **one counter and one reserve**: 24 rounds, 72 to start, 120 at most, a round a
shot whichever hand fires it, and one reload (1.6 s, both cylinders open) fills the counter for both; ammunition is the
shop's `ammo_dual_pistols` (24 for 70). Per hit 17 (head x2.25, limb x0.6) every 0.15 s, spread 2.4 degrees, falloff 10
to 28 m to half, range 45 m. A crane prize (weight 2.5) on both maps, no wall sells it; it is re-cut like the others
(it is in `UpgradeTuning.weapons`: 29.75 a hit, 36 rounds, 108 reserve; its shock arc is #794's). How it is held:
[Weapons in the hands](weapon-hold.md#the-dual-pistols).

**The bat and the axe** were models with no definition. They are melee weapons held as `Melee` (the Swing clip, no
flash, a spark on a hit) with their own hold files, so each shows its own model. They are **found only in the prize
crane, never at the start**, and a player carries two weapons with no separate melee slot ([#410](https://github.com/Ryubara/deadnight/issues/410)),
so one in hand takes a slot a firearm could have had. That is why they are cut stronger than the crowbar (100 a second)
and than the revolver (86): the bat is the crowd weapon (a quick blow that kills a round-1 walker, a sweep that hits
four, 150 a second), the axe is the heavy one (one blow kills a walker of any round up to 10, in every zone, the
slowest, 167 a second). Neither needs ammunition, which is what the slot buys, against a firearm's 190 a second that
runs dry. They are not re-cut at the projector (the re-cut list is the firearms).

**Decided by the maintainer** (on #461, recorded on #410 and #411):

- The hammer is a cosmetic repair tool only: no definition, no slot.
- No grenades from the crane: the grenade is thrown by its own system.
- Carry ([#410](https://github.com/Ryubara/deadnight/issues/410)): a third weapon replaces the one in hand; the
  replaced weapon is disposed of and **goes back into the weapon pool**, not dropped. See
  [Carrying weapons](#carrying-weapons).
- Quick melee on `V` ([#411](https://github.com/Ryubara/deadnight/issues/411)) is the always-available knife blow with
  whatever is in hand, so no melee weapon is needed in a slot for emergencies; it replaced the starting crowbar
  ([below](#quick-melee)).

### The wall tier

**A wall spot sells only the weaker guns, on every map** (the maintainer, [#858](https://github.com/Ryubara/deadnight/issues/858)).
Every weapon has a wall tier, in `WallTier` (`gameplay/weapons/wall_tier.gd`); a wall may sell up to tier 2, and any
weapon above it is **box only**: the prize crane is the only way to it.

| Tier | Weapons | Wall? |
| --- | --- | --- |
| 1, hand | the revolver, the crowbar, the baseball bat, the fire axe, the flare gun | yes |
| 2, the older long guns | the double-barrel, the Tommy gun, the hunting rifle (the best a wall sells) | yes |
| 3, box | every other weapon: the pump 870, MP5, M4A1, PPSh, M249, fifty cal, dual pistols, the ray gun, the freeze gun | **no, the box only** |

- **A weapon not named in `WallTier.TIERS` is tier 3**, so a gun added to the catalogue is in the box until someone
  decides it may hang on a wall; the decision is a row in that table and in this one.
- **It holds on both maps.** The lot's walls are the double-barrel and the rifle; the second map's nine places are
  the revolver, the crowbar, the double-barrel (two walls), the Tommy gun, the bat, the flare gun, the axe and, in the
  cabinet, the rifle. The pump, the MP5 and the M4A1 have no wall on either: the second map asked for new places for them
  and the maintainer's answer was the box only, and the lot follows the same rule.
- **Held by a test.** `test_wall_tier.gd` fails when a wall marker of either map, a weapon either map's tuning prices
  for a wall, or a weapon in a bot's shopping list is above the tier, and when a tier-3 weapon of the catalogue is
  missing from the box's pool of either map. The bots buy at the spots the map has (`BotEconomy` reads the wall
  markers), so their lists follow the walls.

## Quick melee

One button, `V` (the mouse's back button and the pad's d-pad down too), one blow with whatever is in the hands: the
knife of the round-based shooters, always there, never out of rounds, a reliable hit at arm's length. It is not a
weapon: it is not in the catalogue's `IDS`, nobody buys, carries or wins it, and it takes no slot.

| | Quick melee | Crowbar | Baseball bat | Fire axe |
| --- | ---: | ---: | ---: | ---: |
| Per blow (every zone) | 50 | 55 | 60 | 150 |
| Interval | 0.6 s | 0.55 s | 0.4 s | 0.9 s |
| Damage a second | 83 | 100 | 150 | 167 |
| Reach, thickness | 1.6 m, 0.4 | 1.9 m, 0.4 | 1.8 m, 0.45 | 1.8 m, 0.4 |
| Targets in one blow | 1 | 2 | 4 | 2 |
| Head, limb | x1, x1 (flat) | x1, x1 (flat) | x1, x1 (flat) | x1, x1 (flat) |

- **A flat blow (#897).** It does 50 in every zone, so a blow is worth the same wherever it lands. The sweep leaves the
  eye at 1.55 m with a 0.4 m thickness, and a walker's head sphere is at 1.62 m, so the sweep met the *head* on every
  blow at every reach and every aim (measured in the real night, rounds 1 to 9): 40 x 1.5 = 60, which killed round 1
  (50 health) *and* round 2 (58) in one blow, and the tables and the simulator, which read the body, said 40. The
  blow is now the number it shows, and the head bonus is not hidden in the sweep. The bat, the axe and the crowbar
  had the same fault (#924): their tables said 60, 150 and 45 on the body, and the real blow was the head's, 90, 375 and
  68 (the axe killed every walker to round 16 in one blow, not 10). They are flat too now (crowbar 55, bat 60, axe 150
  in every zone). See [hits to kill](#hits-to-kill-by-round).
- **Server:** `CombatAction.quick_melee` (a bit in the command's flags, `NetWire.F_MELEE`, protocol 11) is swept from
  the head along the view with `defs/quick_melee.tres` exactly as a melee weapon's blow is, through the same rewind,
  and hurts as a `melee` hit: the zombie takes the damage, the kill pays the melee price (130). A fixed cooldown of
  0.6 s is each player's own (`CombatServer`): a press inside it is refused (`fire_rejected`, `cooldown`, quiet) and
  not queued. The weapon in hand is left alone: no round is spent, its own cooldown and reload go on. It is refused
  while a grenade is cooking in the hand, and for a downed player.
- **The body turns first:** like a shot from the hip, a press made while the body faces away turns it to the view and
  the blow leaves when it faces it (`PlayerMotionState.melee_ready`; the press is kept for `hip_fire_buffer`).
- **The look:** one blow for every weapon, a short overhead bash with what is in the hands, `Strike_<Class>` from the
  class's own aim pose ([Quick melee on the Soldier](animation.md#quick-melee)): the revolver, the rifle, the shotgun, a
  bat and an axe are each the club. Every client draws every player's blow from the `quick_melee` event.
- **Bat and axe are the strong melee.** They hit harder per blow and per second than the quick melee, so a slot spent
  on one is worth it (a test holds the bat and the axe to 1.5 times its damage a second, the axe to twice its blow, the
  bat to more targets). The crowbar is a slightly stronger blow than the quick melee (55 against 50; a test holds every
  carried melee weapon at the quick melee's blow or more), with a longer reach and two targets, and is one of the
  crane's prizes.
- **Bots:** a bot with no round left and no melee weapon in hand stands and strikes what comes within reach
  (`BotIntent.quick_melee_ok`).
- **On a phone** it is the MELEE button of the [touch controls](touch-controls.md) (#588).

### Hits to kill by round

The maintainer's rule: **one blow on round 1, more from round 2** ("melee attacks with V should not be one tapping
zombies after round 1", [#897](https://github.com/Ryubara/deadnight/issues/897)); every other melee weapon has the same
table since #924. A walker has `health_for_round` health (50 + 8 a round to round 8, then x1.16 a round); a blow is flat
(the same in every zone). Blows to kill a walker, from the real night (`tests/weapons/test_melee_hits_to_kill.gd`,
`tests/weapons/test_quick_melee_hits_to_kill.gd`, `tests/night/test_night_melee.gd`,
`tests/night/test_night_quick_melee.gd`):

| Round | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Walker health | 50 | 58 | 66 | 74 | 82 | 90 | 98 | 106 | 123 | 143 |
| **Quick melee (V), 50** | **1** | **2** | **2** | **2** | **2** | **2** | **2** | **3** | **3** | **3** |
| **Crowbar, 55** | **1** | **2** | **2** | **2** | **2** | **2** | **2** | **2** | **3** | **3** |
| **Baseball bat, 60** | **1** | **1** | **2** | **2** | **2** | **2** | **2** | **2** | **3** | **3** |
| **Fire axe, 150** | **1** | **1** | **1** | **1** | **1** | **1** | **1** | **1** | **1** | **1** |
| Before #897: quick melee (60) | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 3 | 3 |
| Before #924: crowbar (68) | 1 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 3 |
| Before #924: bat (90) | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 2 | 2 |
| Before #924: axe (375) | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |

(The "before" rows are the real night, probed at 0.7, 1.1 and 1.5 m, aimed at the head, chest and legs, walking up
and striking: every blow was in the head zone, so the blow was the table's number times the head's multiplier.)

- **Why 50 for V.** The blow must be at least round 1's health (50) and under round 2's (58), so any number from 50 to
  57 gives this table; the lowest keeps the free blow the weakest it can be. A test holds the blow between the two, so
  retuning the health curve fails it loudly. The count is the health's: every 50 health costs a blow, so it climbs on
  its own as the dead toughen, like the rest of the round curve.
- **Why the crowbar is 55 and not its table's 45.** A weapon found in the crane and carried in a slot must not be worse
  than the free blow on round 1, and 45 would have left a round-1 walker at 5 health after a crowbar blow that V
  finishes. 55 is in the same bracket as V (50 to 57), so the crowbar is the same count with a faster swing, a longer
  reach and two targets (100 a second against 83). A test holds each carried melee weapon at V's blow or more.
- **The bat and the axe keep the numbers their tables always showed** (60, 150): the bat kills round 2 (58) in one blow
  and then needs two, 150 a second with four targets; the axe kills a walker of any round to 10 (143) in one, as the
  design said (the real blow of 375 killed to round 16).
- **Why flat.** A person swinging from the eye cannot choose the zone (the sweep leaves the eye at 1.55 m with a 0.4
  m thickness and the head sphere is at 1.62 m, so it is the head at every reach and every aim, whatever the
  crosshair is on), so a head bonus is a hidden multiplier; a flat blow gives the same count on the head, the chest
  and the legs, near and far (tested), and makes the simulator's body-zone worth the real one. The other way, fixing
  the sweep so zones are reachable (a thinner sphere, a lower start), changes where every blow lands; it is not done.
- **The lighter dead.** A runner (x0.55, from round 4) has 41, 45, 49 and 54 health on rounds 4 to 7, so one blow of V
  still kills it on rounds 4 to 6; a crawler (x0.7, from round 6) has 63 and up, two blows; a brute (x3, from round 8)
  takes 7 to 9. A blow cannot both fell round 1's walker and leave a round-4 runner standing, so the runner stays the
  fast, thin one.
- **The worth the simulator and the bots see.** `WeaponWorth.melee_rate` of the blow, in health a second against the
  round's walker. V: 83 (round 1), 48, 55, 62, 68, 75, 82 (round 7), 59, 68, 79 (round 10). It dips at each step up
  in blows (rounds 2 and 8). A free hand takes a weapon only above 1.5 times that. The crowbar's, the bat's and the
  axe's are the same function of their definitions (a test holds each to the real night's blows).
- **A melee hit is a head hit for the rules.** The zone is the head, so a hit that does not kill pays the headshot hit
  (8 points, not the hit's), and the kill pays the melee kill (130) whatever the zone. Not changed here.

## Carrying weapons

A player carries **two weapons** (`WeaponCatalog.CARRY_LIMIT`), melee ones included: there is no melee slot, and the
bat and the axe take a slot like a gun. A player starts with the revolver alone and a free second hand: the crowbar that
used to fill it is replaced by the [quick melee](#quick-melee), which takes no slot. The swap button (F, d-pad up)
cycles the two weapons once there are two. The keys **1** and **2** take the first and the second weapon in hand (3 is
the third slot's, for the perk that carries three, #687); the slot already in hand, and an empty slot, change nothing. A
slot keeps its place: a weapon bought with full hands takes the slot of the weapon it replaces. The
[HUD](hud.md#the-weapon-slots) shows both slots, the one in hand lit.

Buying a weapon at the wall or taking a prize from the crane with both hands full **replaces the weapon in hand**,
with its magazine and reserve (and its re-cut). The replaced weapon is not dropped on the ground: it is gone, and it
is in the pool again, so the wall sells it again (shotgun, rifle) and the crane can give it again (every crane weapon,
the revolver and the crowbar too). The card of a wall weapon and of a prize on offer says **REPLACES <weapon>** before
the points are paid or the prize is taken. A weapon the player already carries is not offered; the wall sells its
rounds.

Two parts keep it true, each with the weapon in hand as the one given up: the rules (`WeaponCarry`; `PlayerState.weapons`
is the carried list in shop ids, the start weapons in it, and `weapon_released` names what went) and the combat server
(`weapon_replaced`: the dropped weapon, then the new one's `weapon_equipped`; the HUD drops the dropped weapon's rounds
and keeps the other as the one put away, the hands take the new model). The purchase carries the released weapon, so
the two never disagree even when the buyer names none (then the oldest goes).

A re-cut goes with its weapon, but its price step stays (`recuts_lost`): a fresh copy can be re-cut again, and cycling
weapons does not make re-cuts cheaper.

The simulator's players follow the rule (the 1.5 margin is an open question, below): they take a weapon only when it
is worth 1.5 times the weakest they carry, and play the crane only when some prize would be (`REPLACE_GAIN`). Without
that margin they buy in circles. A player who carries no melee weapon falls back on the quick melee's blow in the
simulator (the same definition the server sweeps with), and a free hand is worth that blow: a weapon that does less is
not worth a slot or its price.

## Wonder weapons and status effects

The ray gun and the freeze gun ([#788](https://github.com/Ryubara/deadnight/issues/788)); the numbers and why are
[below](#the-wonder-weapons), the code is this. Their models are #797's (the freeze gun is held as a rifle, the
ray gun as a pistol), and their sounds are #791's
(`EnergySounds`, which hears the combat server's `status_applied` and `status_ended` for the freeze).

- **Ray gun** (`ray_gun`): a `PROJECTILE` weapon like the flare gun, but fast, straight and blue: the bolt is drawn in
  `bolt_core_colour` and `bolt_halo_colour` (`ProjectileView`) and bursts in a swelling blue sphere (`BoltBurst`) the
  size of its splash. The bolt hurts the zombie it meets and the burst every other zombie within `splash_radius` by
  `splash_damage` sliding to `splash_min_fraction` at the edge (`DamageModel.splash`, the flare's own code). **It hurts
  its shooter** by `self_splash_share` (25%) of the splash at the shooter's distance from the burst, measured to the
  chest (`NightServer._hurt_the_shooter`, which hands the number to `_blast_player`, the one place a blast becomes
  damage to a player); a teammate takes nothing.
- **Freeze gun** (`freeze_gun`): a `PROJECTILE` weapon whose bolt does 30 and, where it bursts (a zombie or a wall),
  puts its status on **every zombie in the bloom** (`splash_radius` 2.2 m; `status` frozen for 3 s).
  A frozen zombie stops moving and attacking, keeps its pose and wears an ice shell. **Any hit on it kills it and it
  shatters** (a shot of any weapon but this one's own, a melee blow, the quick melee, a grenade's blast): the hit takes
  all the health the zombie has left, pays the kill the hit pays, and the zombie is gone at once with no corpse and no
  blood while the pieces of ice fly and fade (`zombie_shattered`, `IceShatter`). The hit that freezes never shatters,
  and the freeze gun's own bolt on a frozen zombie only starts the 3 s again (`RulesAction.hit`'s `keeps`).
- **Per zombie kind, not per round** (the maintainer's decision, replacing the research's 1/2/3 bolts by round):
  `ZombieType.freeze_bolts` is how many bolts freeze that kind (an ordinary zombie 1, a **brute 3**: the first two
  only slow it to 40% for 3 s, `chilled`, and the count is kept while the slow lasts) and `ZombieType.freezable`
  says whether it can be frozen at all: **bosses are not** (the headliner is only slowed, whatever the bolts), so a
  boss night keeps its shape. A frozen brute shatters on one hit like any other. The balance simulator does not
  model the freeze, so it needs no round factor.

**Status effects** are one system, not a freeze: a `StatusDef` (`weapons/status/defs/<id>.tres`: `frozen`,
`chilled`) says what a status does while it lasts (`halts`, `speed_scale`, `shatters`, whether the zombie kind gates
it, what a kind that cannot take it gets, the shell's colour) and a `WeaponDef` says which one it puts on and for how
long. The server's `StatusBoard` (owned by `CombatServer`) keeps the seconds left of every status on every zombie and
the bolts counted so far, runs them down on the combat clock and answers `status_applied` and `status_ended` events;
the night server tells the zombie simulation (`ZombieSim.set_status`), and the rules read the board
(`GameRules.statuses`) to kill a hit zombie that is under one that shatters. The snapshot carries the status in the
zombie's mode byte (`ZombieCodec`, protocol 14), so every client draws it (`ZombieView.set_status`, `StatusLook`: one
shell material for every zombie under a status, built in the warm-up). A new element for the re-cut (#794) is a new
`StatusDef` file, an id in `StatusCatalog` and a `status` on the weapon; [what it taught](../research/status-effects.md).

Bots (`BotMotor`, `WeaponWorth`): a frozen zombie is a contact with a `status`; one shot kills it, so the bot shoots it
once and waits half a second for the kill before it tries again, and never in a burst; a bot does not fire the ray gun
at a zombie inside its own splash. `WeaponWorth` rates a weapon whose hit shatters by two pulls to a kill at most.

## The shoulder camera

The camera sits behind and to the right of the player, so the crosshair and the barrel do not line up. A shot is
resolved in two steps: a ray from the camera finds what the crosshair is on (the world or a zombie, ignoring anything
between the camera and the shooter), then the shot leaves the **muzzle toward that point**. If a corner stands between
the muzzle and the point, the muzzle ray hits the corner: the shoulder camera cannot shoot around it. Stepping out
beside the corner makes the same shot land (both are tested and in the capture).

## Hit zones

Zombies are shot at through their zones, not their meshes (`Hitbox`), but the zones are fitted to the meshes: each
look has a set of spheres and capsules (head, body, limbs) for each pose its mode puts it in (moving, striking,
staggering, tearing boards, a boss roaring), the envelope of its bones through that pose's clips, so a shot that touches
the body the player sees counts, on the right zone ([hit zones research](../research/hit-zones.md)). A crawler's zones
are its body on the ground (low, the head half a metre across ahead of its feet), the brute's are 1.18 times a walker's.
The headliner has one more zone, `weak`, a ball on its lit lamp that no other zombie has (the weapons list no
multiplier for it: the rules' x2.2 is the one). The test range draws them as they are. A limb the ray meets first gives
way to the body or head right behind it.

| Zone | Pistol | SMG | Shotgun (per pellet) | Rifle | Flare gun | Crowbar | Bat | Axe |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Head | x2.5 | x2.0 | x1.5 | x2.5 | x1.5 | x1.0 | x1.0 | x1.0 |
| Body | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 |
| Limb | x0.6 | x0.6 | x0.6 | x0.7 | x0.6 | x1.0 | x1.0 | x1.0 |

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
| Double-barrel | 8 pellets, 6 degrees | 22 x 8 | 0.3 s | 2 / 16 (max 32) | 1.8 s | 8 to 22 m (35%) | 30 m |
| Hunting rifle | hitscan, pierces 2 | 95 | 0.5 s | 8 / 40 (max 80) | 2.2 s | 40 to 90 m (80%) | 120 m |
| Flare gun | projectile, lobbed | none: calls the dead (25 m, 8 s) | 0.8 s | 1 / 6 (max 12) | 2.0 s | none | 40 m |
| Crowbar | melee sweep, 2 targets | 55 | 0.55 s | none | none | none | 1.9 m |
| Baseball bat | melee sweep, 4 targets | 60 | 0.4 s | none | none | none | 1.8 m |
| Fire axe | melee sweep, 2 targets | 150 | 0.9 s | none | none | none | 1.8 m |
| MP5 | hitscan, auto | 15 | 0.10 s | 30 / 120 (max 180) | 1.9 s | 12 to 34 m (55%) | 55 m |
| PPSh | hitscan, auto | 10 | 0.055 s | 50 / 100 (max 200) | 2.8 s | 8 to 24 m (45%) | 40 m |
| M4A1 | hitscan, auto | 20 | 0.11 s | 30 / 90 (max 150) | 2.1 s | 22 to 55 m (65%) | 90 m |
| M249 | hitscan, auto, pierces 1 | 15 | 0.09 s | 100 / 150 (max 250) | 5.0 s | 14 to 40 m (55%) | 70 m |
| Fifty cal | hitscan, semi, pierces 4 | 220 | 0.9 s | 5 / 20 (max 40) | 3.4 s | none | 150 m |
| Pump 870 | 6 pellets, 5 degrees, loads by the round | 22 x 6 | 0.65 s | 6 / 42 (max 66) | 2.8 s | 10 to 26 m (45%) | 35 m |

Shots to kill at close range (head / body), against the health in [the rounds table](rounds.md#the-tuning-table):

| Weapon | Round 1 (50) | Round 5 (82) | Round 10 (140) | Damage a second (body) | With reloads |
| --- | --- | --- | --- | ---: | ---: |
| Revolver | 1 / 3 | 2 / 4 | 3 / 6 | 86 | 59 |
| Tommy gun | 2 / 4 | 3 / 6 | 5 / 10 | 187 | 101 |
| Double-barrel | 1 / 1 | 1 / 1 | 1 / 1 | 587 | 147 |
| Hunting rifle | 1 / 1 | 1 / 1 | 1 / 2 | 190 | 123 |
| Flare gun | none | none | none | 0 | 0 |
| Crowbar | 1 / 1 | 2 / 2 | 3 / 3 | 100 | 100 |
| Baseball bat | 1 / 1 | 2 / 2 | 3 / 3 | 150 | 150 |
| Fire axe | 1 / 1 | 1 / 1 | 1 / 1 | 167 | 167 |
| MP5 | 2 / 4 | 3 / 6 | 5 / 10 | 150 | 92 |
| PPSh | 4 / 5 | 6 / 9 | 10 / 14 | 182 | 90 |
| M4A1 | 2 / 3 | 3 / 5 | 4 / 7 | 182 | 111 |
| M249 | 2 / 4 | 4 / 6 | 6 / 10 | 167 | 107 |
| Fifty cal | 1 / 1 | 1 / 1 | 1 / 1 | 244 | 139 |
| Pump 870 (all six pellets) | 1 / 1 | 1 / 1 | 1 / 2 | 203 | 118 |

The shots are the health of the zombie (the table in the page above; `rounds.md` is the source) over the weapon's
damage, rounded up. "With reloads" is the sustained rate over a whole magazine and its reload, the number the
[balance simulator](rounds.md#the-balance-simulator) picks weapons by.

## Why these numbers

- **The starter is a revolver with a one-shot headshot.** At 24 damage and x2.5 on the head, a round-1 zombie (50)
  falls to one headshot or three body shots, so aiming pays from the first minute; by round 5 (82) it takes two
  headshots or four body shots and by round 10 (121) six body shots. The health curve was lowered to the weapons
  that exist (rounds.md, the balance simulator): the shop weapons were stepped up in #265 (rifle 95,
  shotgun 19 a pellet, now the double-barrel's 21) so that buying one is worth rounds.
- **Aiming pays less than it was meant to since the hit zones follow the bodies** (#694): the head is half the chibi
  figure, so the bots aimed at the chest land 64 to 88% of their hits on it. The multipliers stay as the table says and
  the game was retuned around that ([rounds](rounds.md#the-headshot-retune-745)); whether to shrink the head zone is the
  maintainer's ([hit zones](../research/hit-zones.md#not-done-and-what-it-moves)).
- **A weapon can be re-cut once** at the projector: x1.75 damage, x1.5 magazine and reserve limit, filled, for 1,500
  points ([the re-cut](upgrades.md)). The table above is the weapon as shipped; a re-cut one has its damage in the
  column multiplied and its magazine and reserve limit grown, and kills in fewer shots (a re-cut revolver, 42 a hit,
  kills a round-10 zombie in 3 body shots). This is what lets the health curve climb faster than the shipped weapons
  could follow. Since #794 the re-cut is each weapon's own (`RecutProfile`): the revolver fires slower and bursts, the
  flare gun leaves fire, and the flare gun carries 3 shots in all (1 and 2 in reserve), 6 re-cut.
- **Each weapon has one job.** The SMG is volume at short range (the most damage a second, a short magazine of
  patience before the reload); the double-barrel is a close wall that holds two shells and is slow to reload; the
  rifle is the precision and the line (it passes through two zombies, each blow 40% weaker, which rewards lining the
  dead up); the flare gun is crowd control: it draws the dead away from the team for a few seconds and hurts no one;
  the crowbar never runs dry and pays the melee kill bonus (130 points) for the risk of being in reach.
- **The double-barrel is two shells and a break-open reload (#684).** It replaced the pump (6 shells, 19 a pellet, 0.8
  s): a magazine of 2, a 0.3 s gap between the barrels, a 1.8 s reload that breaks it open, loads both shells and
  snaps it shut (a single shell left in it is topped up the same way), 22 a pellet in a 6 degree cone. Against a
  round-10 zombie it kills as many a second as the pump did (one pull a kill, the number the weapon pick compares), so
  the price of 900 still buys what it did, and the balance simulator's medians stayed or rose a round ([the
  numbers](../research/balance-simulator.md#the-double-barrel-684)). Each pull is a 176-point wall, so a round-10
  zombie (121) still falls to one; what changed is that two kills are all it holds before a two-second wait. Its
  reserve is 16 shells, 32 at most.
- **The shotgun cannot farm points.** Pellets add up to one hit for the rules, and its damage falls to 35% by 22
  m, so it is a close weapon by its own numbers, not by a rule.
- **Ammo is the other economy.** Reserves are small on purpose (a round-10 zombie is 5 revolver body shots), so
  headshots and melee are worth more than the points they pay. Ammunition is sold ([Rounds](rounds.md#ammunition));
  the weapon carry limit is not decided here; see the open questions.

## The nine new weapons (#785)

**Six are built, three are planned.** Nine weapons are added to the eight (seventeen in all): six firearms
([#793](https://github.com/Ryubara/deadnight/issues/793), **built**), the two wonder weapons and the status effects they
need ([#788](https://github.com/Ryubara/deadnight/issues/788)) and the dual pistols
([#789](https://github.com/Ryubara/deadnight/issues/789)). This section is the one place their numbers are decided; the
build issues copy them into `defs/<id>.tres`. The evidence is [the roster research](../research/weapon-roster.md), the
re-cut of each is [on the re-cut page](upgrades.md#the-re-cut-plan-for-seventeen-weapons-785). Falloff and zones read as
in [the arsenal](#the-arsenal); the limb multiplier is x0.6 unless a row says otherwise.

### The numbers

Per hit is the body zone at point blank; the head multiplier is per pellet. "Working id" is the catalogue id and the
shop id suffix (`weapon_<id>`); the display name is a tuning string ([names](#display-names-original-names-the-same-guns)).

| Weapon (working id) | Kind | Per hit | Interval | Magazine / reserve (max) | Reload | Spread | Head | Falloff start to end (floor) | Range |
| --- | --- | ---: | ---: | --- | ---: | ---: | ---: | --- | ---: |
| MP5 (`mp5`) | hitscan, auto | 15 | 0.10 s | 30 / 120 (180) | 1.9 s | 1.4 deg | x2.0 | 12 to 34 m (55%) | 55 m |
| PPSh (`ppsh`) | hitscan, auto | 10 | 0.055 s | 50 / 100 (200) | 2.8 s | 3.2 deg | x1.5 | 8 to 24 m (45%) | 40 m |
| M4A1 (`m4a1`) | hitscan, auto | 20 | 0.11 s | 30 / 90 (150) | 2.1 s | 1.0 deg | x1.75 | 22 to 55 m (65%) | 90 m |
| M249 (`m249`) | hitscan, auto, pierces 1 | 15 | 0.09 s | 100 / 150 (250) | 5.0 s | 2.6 deg | x1.75 | 14 to 40 m (55%) | 70 m |
| Fifty cal (`fifty_cal`) | hitscan, semi, pierces 4 (x0.7 each) | 220 | 0.9 s | 5 / 20 (40) | 3.4 s | 0.15 deg | x2.0 (limb x0.8) | none (100%) | 150 m |
| Pump 870 (`pump_870`) | hitscan, semi, 6 pellets | 22 x 6 | 0.65 s | 6 / 42 (66) | 2.8 s | 5.0 deg | x1.5 | 10 to 26 m (45%) | 35 m |
| Dual pistols (`dual_pistols`) | hitscan, auto, alternating hands | 17 | 0.15 s (0.30 s a gun) | 24 / 72 (120) | 1.6 s | 2.4 deg | x2.25 | 10 to 28 m (50%) | 45 m |
| Ray gun (`ray_gun`) | `PROJECTILE`, 55 m/s, flat, 1.3 s of flight | 300 direct (head x1.5, limb x0.7) + blast 160 | 0.45 s | 10 / 40 (60) | 2.6 s | 0 | x1.5 | none | 70 m |
| Freeze gun (`freeze_gun`) | `PROJECTILE`, 45 m/s, flat, 1.3 s of flight | 30 direct, no blast, freezes | 0.8 s | 6 / 24 (36) | 3.0 s | 0 | x1.0 | none | 60 m |

What each one is for (the genre's role, in our numbers):

- **MP5, the reliable SMG**: a precise automatic (1.4 degrees, x2 head) that is bought, not gambled for; a head hit on a
  round-5 zombie is 3 shots. It does what the Tommy gun does a little more kindly and a little slower.
- **PPSh, the drum**: the most bullets (50, and 200 at most) and the worst aim (3.2 degrees, x1.5 head, 45% at 24 m):
  it sprays bodies and rewards a crowd at your feet. Box only.
- **M4A1, the carbine**: the all-rounder at range (1.0 degree, 65% of its hit still at 55 m, a magazine of 30 on an
  automatic): the best aim and reach of the automatics, a steady body-shot rate (97 a second on round 10, against the
  rifle's 90), dearer than the rifle, with none of its piercing and none of its one-shot heads.
- **M249, the belt-fed**: 100 rounds, a **5 second reload** that is the cost (a crowd takes you while it is open);
  pierces one zombie; the most kills from one load (62 on round 5). Box only.
- **Fifty cal, the anti-materiel rifle**: five rounds, each a body kill on any round to 13 (a head kill to 18),
  piercing four zombies in a line (x0.7 each), no falloff at all; slow (0.9 s) and starved of ammunition (20, 40 at
  most). Box only: it is the late-round weapon the model cannot value (the simulator does not model piercing).
- **Pump 870, the cheap wall**: six shells of 132 close in: one shell kills any zombie to round 9 and two to round 14;
  short range (35 m), slow (0.65 s), a long tube to refill (2.8 s). It is the cheapest wall (700) and the weakest
  late, so it gets an element on its re-cut ([fire](upgrades.md#the-four-elements)).
- **Dual pistols, the sidearm pair**: two revolvers' worth of rate at a lighter hit (17, x2.25 head), the biggest magazine
  of a pistol (24) and no precision (2.4 degrees on every pull). Box only. The mechanics are
  [below](#the-dual-pistols).
- **Ray gun and freeze gun, the pair**: [below](#the-wonder-weapons).

### Where they are and what they cost

**Walls (decided after this page, #858):** a wall sells only the weaker guns, so the pump, MP5 and M4A1 are the box's alone
on both maps; the wall prices and places below are #785's plan and are not built.

The lot's prices are in points; the second map's are its own ratios to its link price **P = 450**
([the shop formula](smallmap.md#the-shop-formula-rows-22-to-25)) and each stays within 10% of its ratio
(`test_smallmap_economy.gd` recomputes them). "Weight" is the crane's pool weight (`crane_play`), against the existing
eight's 13 (shotgun 4, rifle 3, Tommy gun 2, flare gun 1, revolver 1, crowbar 1, bat 0.5, axe 0.5): the pool is **28.5**
with the nine. A wall weapon is also in the crane, as the shotgun and rifle are; a weapon the player carries is never
drawn.

| Weapon | The lot | The small map | Crane weight | Ammunition: rounds for points |
| --- | --- | --- | ---: | --- |
| Pump 870 | the crane only | the box | 2 | 6 for 80 |
| MP5 | the crane only | the box | 2 | 45 for 90 |
| M4A1 | the crane only | the box | 1.5 | 30 for 90 |
| PPSh | crane only | the box | 2 | 75 for 110 |
| M249 | crane only | the box | 1.5 | 100 for 150 |
| Fifty cal | crane only | the box | 1.5 | 5 for 100 |
| Dual pistols | crane only | the box | 2.5 | 24 for 70 |
| Ray gun | crane only | the box | 1.5 (5.3%) | 4 for 180 |
| Freeze gun | crane only | the box | 1.5 (5.3%) | 3 for 150 |

- **No wall sells them (#858).** The first plan priced the pump (700), the MP5 (1,300) and the M4A1 (1,600) as walls
  above the rifle, by what the simulator says each is worth ([the research](../research/weapon-roster.md#the-balance-simulator-run):
  the MP5 and the M4A1 about two and a quarter rounds, the pump a neutral buy). The maintainer decided otherwise: wall
  spots are for the weaker guns ([the wall tier](#the-wall-tier)), so these three come only from the box, on the lot
  and on the second map, and neither map has a place or a price for them. Their worth is why they are in the box's
  pool at weights 2, 2 and 1.5, and a box-only gun is bought as a gamble of 425 or the lot's crane price, not as a
  sure buy. The balance gate was run with them on walls ([the run](../research/weapon-roster.md#the-balance-simulator-run)):
  read again with them in the box only.
- **The box's pool is the one shop item**, so the weights above are the only thing the crane's tests need
  (`test_crane_pool.gd`: every weapon of the catalogue is in the pool, and 10,000 first rolls are spread by the
  weights). With them the average player's night is up by two rounds ([the run](../research/weapon-roster.md#the-balance-simulator-run)).

### Where each stands against the others

Kills a second on a round's zombie, the weapon's cycle with its reload (`WeaponWorth.sustained_dps` against that
round's health), a body hit and a head hit, then the kills one load (magazine plus reserve) makes with head hits. The
weapon pick of the simulator's players reads the first number.

| Weapon | Kill rate on round 5, body / head | Round 10 | Round 15 | Kills one load makes, round 10 (head) | Price or source |
| --- | ---: | ---: | ---: | ---: | --- |
| Revolver | 49 / 99 | 56 / 113 | 57 / 137 | 17 | start |
| Pump 870 | 73 / 73 | 62 / 125 | 84 / 126 | 48 | crane |
| Double-barrel | 68 / 68 | 116 / 116 | 117 / 117 | 18 | wall 900, crane |
| Dual pistols | 75 / 126 | 71 / 161 | 76 / 162 | 24 | crane |
| PPSh | 82 / 123 | 84 / 126 | 87 / 133 | 15 | crane |
| Tommy gun | 98 / 197 | 92 / 168 | 97 / 185 | 25 | crane |
| MP5 | 83 / 167 | 85 / 171 | 90 / 172 | 30 | crane |
| M4A1 | 91 / 151 | 97 / 155 | 104 / 174 | 24 | crane |
| M249 | 97 / 146 | 100 / 166 | 106 / 183 | 42 | crane |
| Hunting rifle | 105 / 105 | 90 / 180 | 121 / 181 | 48 | wall 1,200, crane |
| Fifty cal | 51 / 51 | 88 / 88 | 89 / 178 | 25 | crane |

**None is strictly better than another at its price or source**: each pair that one beats on a number above is parted
by something else (the price or the rarity, the reload, the aim and the head multiplier, the range, the piercing). The
cases to read: the **MP5** beats the Tommy gun a little on aim, falloff and load and loses a little on body rate, and
costs 1,300 for a sure buy against a 550 gamble; the **M4A1** beats the rifle on body rate to round 10 and on
magazine, uptime and the re-cut (11.5 against 10.1, and 14.5 against 11.4) at 400 more, and loses to it on piercing,
range (the rifle is 120 m) and the one-shot head kill (the rifle's 237 kills a head to round 13); the **M249** beats the
Tommy gun on load and a little on rate and pays a 5 second reload and the box's odds; the **dual pistols** beat the
revolver on rate and magazine and lose it the one-shot head (the revolver kills a round-1 zombie with one head hit); the
**fifty cal** is the slowest and the leanest of all and the only one that kills a line of zombies and a late
round's heavy ones in one hit. The only exception to "at its price" is the **wonder pair**, which are one-hit kills
for most of the night and are held down by rarity and ammunition, not by price ([below](#the-wonder-weapons)).

### The six firearms (#793)

The six are `defs/<id>.tres` (`mp5`, `ppsh`, `m4a1`, `m249`, `fifty_cal`, `pump_870`) with the numbers above, in
`WeaponCatalog.IDS` and `UpgradeTuning.profiles` (so each is re-cut once, [the plan](upgrades.md#what-each-weapon-becomes)).
`game/tests/weapons/test_new_firearms.gd` pins every number and the three behaviours below.

- **The .50 calibre goes through four zombies.** `penetration` 4, each one 0.7 of the one before (220, 154, 108, 76,
  53 on the body): the shot is the rifle's (`AimResolver.trace_one`) with a longer line, so a wall still stops it.
- **The M249 shoots wider on the move.** `moving_spread_deg` 2.4: its 2.6 degree cone grows by that much at a full run
  (0 standing, linearly between): 5.0 degrees at a run. The night server gives the fire action a `move` share
  (`CombatAction.fire`, the body's ground speed over `run_speed`), and the spread is still seeded by the match, the
  shooter and the shot number, so a client that replays a shot scatters it the same way. No other weapon has one.
  Its **5 second reload** is the other cost, and it pierces one zombie.
- **The pump loads a round at a time, and a shot ends the reload.** `reload_by_round`: `reload_time` (2.8 s) is the whole
  tube from empty, so a round takes 2.8 / 6 = 0.47 s, each is in the magazine the moment it goes in (the HUD's count
  rises a round at a time: `reload_round`), and a pull of the trigger with at least one round in ends the reload and
  fires (`reload_interrupted`, the rounds loaded stay). With none in, the shot is refused as before (`reloading`). A
  reload of two rounds takes 0.93 s. The reload perk quickens each round. The motion is a loop of one cycle a round
  (`ReloadMotion.loop_rounds`): the shell is fetched from the belt and put in the port, `shell_in` and `pouch` sound for
  each, and a shorter reload plays the lead-in, that many cycles and the rack of the pump.
- **The bots** fire a pump that is still loading as soon as it has a round (`BotMotor`); every other weapon waits for its
  reload to end.
- **Where they are**: the box of both maps, at #785's weights, and nowhere else: the maintainer decided (#858) that a wall
  sells only the weaker guns, so the pump, MP5 and M4A1 are not sold (#785's wall prices of 700, 1,300 and 1,600 and the
  second map's three wall places were taken out before the build merged). Their rounds are sold at the locker or in the
  shop's ammunition items at #785's prices.
- **Names are strings.** `display_name` is "Reel Gun", "Usher SMG", "Matinee Carbine", "Double-Feature Gun", "Fifty cal"
  and "Popper" (the maintainer's choice, #857; the ids stay `ppsh`, `mp5`, `m4a1`, `m249`, `fifty_cal`, `pump_870`); the
  HUD, the cards, the prompts and the feed read them from the definition.

### The dual pistols

The decision for [#789](https://github.com/Ryubara/deadnight/issues/789), from how the genre fires two guns
([research](../research/weapon-roster.md#dual-pistols)):

- **One trigger, alternating hands.** Each pull fires the next hand's gun (right, left, right...): one trigger on every
  input (mouse, pad, touch), no second button to learn. Each hand has its own cooldown (0.30 s), so a shot leaves every
  0.15 s. `automatic = true`: holding the trigger keeps alternating.
- **Two muzzles, one aim.** Each shot leaves its own hand's `Muzzle` (the left and right guns, 0.18 m either side of the
  aim line at the server's muzzle offset) toward the same crosshair point; the server still owns the muzzle
  ([built for a server](#built-for-a-server)).
- **Ammunition.** The HUD shows one number, 24, which is two magazines of 12 shot in turn; the reserve is 72 (120 at
  most). **One reload for both**, 1.6 s with both hands (an independent reload per hand, as the modern shooters do, is
  not built: the first version keeps one counter).
- **Aim.** The aim button gives the same aim weight (camera and the two arms) as every weapon, with **no extra
  tightening**: 2.4 degrees on every pull, and no zoom beyond the hip-fire's, which is what the genre's dual pistols give
  up (they cannot aim down the sights) for the doubled ammunition and rate.
- **The animation** needs the two-handed hold ([#789](https://github.com/Ryubara/deadnight/issues/789), `weapon-hold.md`):
  both hands carry a gun, no support hand; the swap, reload and quick melee clips play with both guns in the hands.
- **The re-cut** is the standard one with an element, [shock](upgrades.md#the-four-elements).

### The wonder weapons

For [#788](https://github.com/Ryubara/deadnight/issues/788). Both are `PROJECTILE`s in the flare gun's flight code
(`ProjectileState`, `projectile_burst`), found **only in the crane**, weight 1.5 each of 28.5 (5.3% of a spin; about 10%
that one of the two shows in a spin and about 15% in an average night's one to two plays). A player who gives one up
puts it back in the pool as every weapon does.

| | Ray gun | Freeze gun |
| --- | --- | --- |
| The shot | a bolt, 55 m/s, no gravity, bursts on the first zombie or wall | a bolt, 45 m/s, no gravity, bursts on the first zombie or wall |
| Direct hit | **300** (head x1.5 = 450, limb x0.7): a body kill to round 15 (282), a head kill to round 18 (429) | 30 (a hit that does no more than pay a hit) |
| Blast | **160 at the centre, sliding to 30% at 3.0 m**; only the others in the blast take it (the one hit takes the direct hit only, as the flare); a line of sight is not asked | none; a **frost bloom, 2.2 m radius**, at the burst |
| Hits the shooter | **25% of the blast** inside 3.0 m (40 at the very centre); a teammate takes nothing (as the grenade's rule) | no |
| The effect | none: it is a hard hit and a blast | everything in the bloom **freezes for 3 s** (below) |
| Ammunition | 10 / 40 (60), reload 2.6 s, 0.45 s a shot | 6 / 24 (36), reload 3.0 s, 0.8 s a shot |
| Re-cut (once, 1,500) | direct 525, blast 280, magazine 15, reserve 60 (90): a body kill to round 19, a head kill to 22 | magazine 9, reserve 36 (54), **the bloom 2.8 m** (`UpgradeTuning.bloom_multiplier`) |

**The freeze.** A frozen zombie stands still for **3 seconds**: it neither walks nor strikes, and it keeps what it was
tearing. **Any hit on a frozen zombie kills it at once and shatters it** (any weapon of any player, a blast, a melee
blow, a grenade; **not** the freeze gun's own bolt, which only refreshes the 3 s): the kill pays what its killer's hit
would (the melee price of 130 for a knife blow, which is the genre's own freeze-then-knife play) and the client breaks
it into pieces (a gib, never a rule). Thawed after 3 s, it goes on, with its health as it was.

- **It does not pass through anything.** The bolt bursts on the first zombie or wall; the 2.2 m bloom is the several
  zombies it freezes (a cluster of three or four in the alley). Passing through a line would make a lane of ice for 3
  s of the whole night.
- **The freeze takes more bolts of a tougher kind, not of a later round** (the maintainer's decision, in place of
  the research's "one bolt on rounds 1 to 10, two on 11 to 20, three on 21 to 30"): **an ordinary zombie freezes on
  the first bolt, a brute on the third**; the first two slow it to 40% for 3 s (a bolt and a half-frozen walk). The
  number is `ZombieType.freeze_bolts`, data.
- **A boss is not freezable** (`ZombieType.freezable`, data): the headliner is slowed to 40% for 3 s and takes the
  direct hit, whatever the bolts; so a boss night is not trivialised, as the genre's Pentagon Thief is only slowed. A
  brute (x3 health) freezes and a shatter kills it: that is what the gun is for.
- **The ammunition is the limit**: 30 bolts a load and 36 at most, each worth a few zombies, against a night's
  hundreds (round 20 sends 54 alone); a bolt costs 50 points of ammunition against a kill's 60 to 70.

**How the pair stays strong without ending the curve.** (1) **Rarity**: 5.3% a spin each, so most nights have neither
(the gate's average cells, with them in the pool, gain two rounds, not ten). (2) **Ammunition**: both are small
reserves with dear rounds (45 and 50 points a round against the rifle's 10 and the Tommy gun's 1.5), and the crane's
prize is only a weapon the player lacks. (3) **They have a ceiling by round, not a wall**: the ray gun's one-hit window
closes at round 15 body and 18 head (21 and 22 re-cut), then it needs two or three bolts a zombie; the freeze
stays one bolt for an ordinary zombie and its ceiling is the brute's three; both are numbers in the data.
(4) **Two weapon slots**: either one is a slot
not holding a re-cut rifle, and the re-cut it takes is 1,500 or 3,000 the player does not spend on a perk. (5) **Bosses
and special rounds keep their shape**: the freeze does not hold a headliner, and a Stampede or a Crawl Space still
sends more than 30 bolts. (6) **The ray's blast hurts the shooter**: close shots are a choice.

### Display names: original names, the same guns

Several real names are trademarks (Barrett, Remington, probably MP5 and M4A1). **The maintainer's decision
([#857](https://github.com/Ryubara/deadnight/issues/857)): use alternative names and keep the same gun design.** A
gun whose name is a maker's name, a brand or a model designation gets an original name in the drive-in's voice
(a concession stand, a projectionist, the picture show); ids, models, stats and sounds stay as they are, and the
working ids below are what the code, the shop (`weapon_<id>`) and the tests call it. `display_name` is the one string
the HUD, the prompt cards, the crane's reveal, the feed and "Re-Cut <name>" read (`WeaponDef.display_name`; the
re-cut is the word Re-Cut before it). The wall plaques are the lot's own text, which the test below reads as well.

| Working id | Shown to the player as | Why |
| --- | --- | --- |
| `mp5` | **Usher SMG** | A Heckler and Koch designation; the ushers carry the reliable, bought-not-gambled gun |
| `ppsh` | **Reel Gun** | A Soviet designation (not a brand), but a model name: the round drum is a film reel |
| `m4a1` | **Matinee Carbine** | A Colt designation; the all-rounder of the early show |
| `m249` | **Double-Feature Gun** | The US designation and a maker's brand; two reels' worth of belt (100 rounds). "Marathon" is another game's title, so it is not used |
| `pump_870` | **Popper** | A Remington model; the pump is the concession stand's popcorn popper |
| `fifty_cal` | Fifty cal (unchanged) | A calibre, not a brand: "Barrett" is dropped, the plain word stays |
| `ray_gun` | **Moonbeam Pistol** | "Ray Gun" is the reference genre's famous name, which GDStudio games do not copy |
| `freeze_gun` | **Snow-Cone Gun** | Paired with the ray gun's rename: the cold gun is the concession's snow-cone machine |
| `dual_pistols`, `pistol`, `shotgun`, `rifle`, `flare_gun`, `crowbar`, `baseball_bat`, `fire_axe` | unchanged | Plain words of the language, no maker in them |
| `smg` | Tommy gun (unchanged) | The Thompson's nickname became the plain word for the gun; "Thompson" itself, the maker, is on the banned list. **Kept for the maintainer to confirm** |

The pull requests that add the guns ([#826](https://github.com/Ryubara/deadnight/pull/826) the six firearms,
[#823](https://github.com/Ryubara/deadnight/pull/823) the ray and freeze guns) take these names when they land: until
a gun is in the catalogue its row is only a promise, and the moment its id is, `test_weapon_names` fails unless its
`display_name` is the chosen one.

**The gate** is `game/tests/weapons/test_weapon_names.gd` with `weapon_name_rules.json` beside it: the `banned` list
(makers, brands, model designations and other games' famous names, matched as whole words, so "Colton" and "Sawmill"
pass) and the `chosen` names above. It reads the name of every catalogue weapon and its re-cut, the text of every wall
plaque and sign in both maps, the feed's lines and the challenges' texts, and fails on any that holds a banned term,
on two weapons with one name, and on a chosen name that is not shown. To add a name to the list, add a line to the
JSON; to name a new gun, pick a name that is not on it.

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
fuse keeps running**: it is spent, it is not given back, and it hurts whoever is near by the player blast rule below
(a player already on the ground takes no blow), which makes a revive during a cook a risk the team can see: a teammate
kneeling at the downed player is inside the full radius. The throw that follows is refused (`player_downed`); a
revived player starts again with a fresh pin.

**In the night.** The server throws for every player on their command's grenade buttons (G, the right shoulder
button and the touch Grenade button for the overarm throw; H and the left shoulder button for the toss), only while a
round is on and the player is up and has one. The count drops at the pin, so a grenade cooked to the end and let go
in the hand is spent and downs the thrower ([blast on players](#blast-on-players)). The Soldier cooks and throws
with his own clips. Wired and proven in #351: [Grenades research](../research/grenades.md#in-the-night-351).

| Thing | Number |
| --- | --- |
| Fuse | 3.0 s from the pin; cooking spends it in the hand; held to the end it goes off in the hand |
| Overarm | 14 m/s, lifted 5 degrees; keeps half of the thrower's speed; a level throw lies 10 m out, the longest lob 12 m |
| Underarm | 7 m/s, lifted 18 degrees; lies 4 to 5 m out |
| Flight | a heavy shell: gravity 22 m/s2; floor bounce keeps 22%, wall bounce 30%, 45% lost along the surface; under 2.5 m/s it rolls, 9 m/s2 of friction, stops under 0.3 m/s |
| Zombies | a zombie is an upright capsule (0.4 m across the arms, as tall as its head); running into it leaves 4% of the speed into it, 5% along it and a 0.2 m/s shove away, so the grenade drops at its feet or bounces off under 1 m, never through and never far |
| Blast | 150 at the centre and out to 2 m, sliding to 0 at 8 m |
| Cover | a line from the blast (0.25 m up) to each of the six hit parts; a part with something solid in the way takes nothing |
| Shares of the blast | legs 25% each, body 25%, arms 10% each, head 5% (a blast goes off low) |
| Knockback, stun | up to 7 m/s along the ground and 3 m/s up, 1.6 s stun, both falling off like the damage |
| Players | the thrower alone: all of their health in the hand and within 1 m of the blast, then less to nothing at 8 m, none behind a wall; a teammate takes nothing ([blast on players](#blast-on-players)) |
| Authority | hand within 1 m of 1.45 m above the server's feet; client speed at most 7.5 m/s; a dropped grenade starts 0.3 m above the feet |
| Carry | start with 2, every round start tops up to 3, at most 5; the shop sells 2 for 150 (+5 a round) |
| Kill points | 40 for a zombie the blast kills (a hit that does not kill pays the usual 4) |

### Blast on players

The maintainer, 2026-11-03: grenades hurt the player too; 100% if it blows up in the hand, full damage only super close,
falling off with distance. And, the same day (#856), **only the thrower takes it**: a teammate in a player's blast takes
nothing and sees no hurt line. One rule (`PlayerBlast`, `game/gameplay/rules/player_blast.gd`) serves every blast that
can hurt a player; the grenade is its first user and the ray gun's splash on its own shooter (25%) is the second.

- **A share of the player's health bar**, not a damage number: full is always "down", from full health or not, and a
  tonic that raises the bar does not make a grenade at the feet safer.
- **In the hand: all of it**, wall or no wall (the grenade is in their hand).
- **Full radius 1 m** (`player_full_radius`): a body's width and an arm's reach, so a grenade in the hand, at the feet or
  against the player takes all of it and one a pace away is already less. A grenade dropped at a downed player's feet
  takes a kneeling reviver whole.
- **Then it eases out to nothing at the blast radius (8 m)**: `(1 - t)^2`, t the way across from 1 m to 8 m. 2 m away is
  73% of the health, 3 m 51%, 4 m 33%, 5 m 18%, 6 m 8%, 7 m 2%: a few metres off hurts and rarely downs, and two close
  ones in a row will. The ease is steep first so that "close" stays deadly and the long tail is a graze that mends.
- **Walls:** the line from the blast to the chest (1 m up) must be clear of walls and props (cover slack 0.12 m); a
  player is no cover.
- **Only the thrower takes damage (the maintainer, #856).** #835 first hurt the team on the same curve and asked; the
  answer is no friendly fire from a grenade. A teammate at 0.5 m takes 0, gets no red arc, no `player_hurt` and no feed
  line; the thrower at 0.5 m takes the full share. The server does not even name a teammate (`player_blasted` is sent
  for the thrower only). A downed thrower is not counted (the rules refuse a blow on them), so the grenade a downed
  player dropped at their reviver's knees hurts no one. The dead are untouched by this: they take the blast as before.
- **Shown:** the thrower's red arc points at the blast; the feed says `YOUR OWN GRENADE HIT YOU  -42` on their own screen
  (a blast that does not down), and on a down `RUBY BLEW THEMSELVES UP` on every screen. The server's `player_hurt` and
  `player_downed` carry `harm` (`grenade`) and `by_id`.
- **Bots** throw only where the blast takes under a tenth of their own health (`BotGrenadier.harmless_apart`, 5.8 m,
  planned 7 m from the bot) and keep no distance from their teammates, who take nothing. A bot keeps out of its own
  live grenade: it steps out of reach, never retreats toward it, and stands and fights instead of walking on
  ([measured on the grenades page](../research/grenades.md#the-bots-and-their-own-grenade-872)).

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

- **Shop weapons: stepped up (#254, #265).** The rifle (95, 0.5 s) and the shotgun (19 a pellet, 0.8 s; the
  double-barrel since #684) are applied; the reasoning and the reference are in [round
  scaling](../research/round-scaling.md). What is still missing is a way for a weapon to keep pace with health that
  compounds (the original's Pack-a-Punch): an issue.
- **The carry limit: built (#410), as the maintainer decided it.** Two weapons, no melee slot, a third replaces the
  one in hand and goes back into the pool ([Carrying weapons](#carrying-weapons)). Three balance choices were made to
  keep the balance gate and are **open for the maintainer**, not decided: the revolver and the crowbar are in the
  crane pool at weight 1 each (the only way back for them; the crowbar is no longer a start weapon), the stampede is
  cut from 140% to 110% of the count so the gate holds with two weapons, the simulator's players replace a weapon only
  for one worth 1.5 times more. The fourth, the starting crowbar, was replaced by the quick melee
  ([#411](https://github.com/Ryubara/deadnight/issues/411)): a player starts with one weapon and a free slot, and the
  gate holds (see the [balance
  simulator](../research/balance-simulator.md#the-quick-melee-replaces-the-starting-crowbar-411)).
- **The flare: no damage, a lure (#439).** The maintainer: it acts like a monkey bomb or a pipe bomb, no damage for
  now. Where it bursts it burns for `lure_seconds` (8) and every zombie within `lure_radius` (25 m) walks to it
  instead of to a player ([how the dead behave](zombies.md#the-flare-lure)). Its damage and splash are 0 in the
  definition, so an upgrade's damage multiplier does nothing to it. A grenade still hurts the thrower alone
  (`player_blasted`).
- **Reload as a skill.** A magazine swap that rewards a timed second press, and cancelling a reload by sprinting, wait
  for the controller (#14).
- **Quick melee: built (#411)**, [above](#quick-melee). Open: a touch button for it, and whether a blow should
  cancel a reload (it does not).
