# Weapons

How a shot works, what it costs a zombie and what each weapon is for. The code is `game/gameplay/weapons/`; every
number is in one `.tres` per weapon (`defs/`), and the tests pin the behaviour (`game/tests/weapons/`). The economy it
feeds is in [Rounds, points and fuel](rounds.md); how it was built is in [Weapon firing](../research/weapon-firing.md).

## Built for a server

The server decides every hit. The client shows the shot at once and the server's events correct it.

- **Client, at once:** muzzle flash, tracer, impact spark and the sound request, drawn from the shooter's own view with
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

## The shoulder camera

The camera sits behind and to the right of the player, so the crosshair and the barrel do not line up. A shot is
resolved in two steps: a ray from the camera finds what the crosshair is on (the world or a zombie, ignoring anything
between the camera and the shooter), then the shot leaves the **muzzle toward that point**. If a corner stands between
the muzzle and the point, the muzzle ray hits the corner: the shoulder camera cannot shoot around it. Stepping out
beside the corner makes the same shot land (both are tested and in the capture).

## Hit zones

Zombies are shot at through their zones, not their meshes: a head sphere, a body capsule and four limb capsules
(`Hitbox`). The test range draws them as they are.

| Zone | Pistol | SMG | Shotgun (per pellet) | Rifle | Flare gun | Crowbar |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Head | x2.5 | x2.0 | x1.5 | x2.5 | x1.5 | x1.5 |
| Body | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 | x1.0 |
| Limb | x0.6 | x0.6 | x0.6 | x0.7 | x0.6 | x0.75 |

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
| Pump shotgun | 8 pellets, 5 degrees | 11 x 8 | 0.9 s | 6 / 24 (max 48) | 2.4 s | 5 to 18 m (25%) | 30 m |
| Hunting rifle | hitscan, pierces 2 | 70 | 0.55 s | 8 / 32 (max 64) | 2.2 s | 40 to 90 m (80%) | 120 m |
| Flare gun | projectile, lobbed | 90 + blast 60 (3 m) | 0.8 s | 1 / 6 (max 12) | 2.0 s | none | 40 m |
| Crowbar | melee sweep, 2 targets | 45 | 0.55 s | none | none | none | 1.9 m |

Shots to kill at close range (head / body), against the health in [the rounds table](rounds.md#the-tuning-table):

| Weapon | Round 1 (60) | Round 5 (132) | Round 10 (213) | Damage a second (body) |
| --- | --- | --- | --- | ---: |
| Revolver | 1 / 3 | 3 / 6 | 4 / 9 | 86 |
| Tommy gun | 3 / 5 | 5 / 10 | 8 / 16 | 187 |
| Pump shotgun | 1 / 1 | 1 / 2 | 2 / 3 | 98 |
| Hunting rifle | 1 / 1 | 1 / 2 | 2 / 4 | 127 |
| Flare gun | 1 / 1 | 2 / 2 | 3 / 3 | 112 + blast |
| Crowbar | 1 / 2 | 2 / 3 | 3 / 5 | 82 |

## Why these numbers

- **The starter is a revolver with a one-shot headshot.** At 24 damage and x2.5 on the head, a round-1 zombie (60)
  falls to one headshot or three body shots, so aiming pays from the first minute, and by round 5 (132) it takes three
  headshots, so a starting weapon stops being enough and the shop matters (as [the economy](rounds.md) assumes).
- **Each weapon has one job.** The SMG is volume at short range (the most damage a second, a short magazine of
  patience before the reload); the shotgun is a close wall; the rifle is the precision and the line (it passes through
  two zombies, each blow 40% weaker, which rewards lining the dead up); the flare gun is crowd control with a risk of
  being too close (the blast hurts anyone near the point of impact, the shooter's own party excluded for now); the
  crowbar never runs dry and pays the melee kill bonus (130 points) for the risk of being in reach.
- **The shotgun cannot farm points.** Pellets add up to one hit for the rules, and its damage falls to a quarter by 18
  m, so it is a close weapon by its own numbers, not by a rule.
- **Ammo is the other economy.** Reserves are small on purpose (a round-10 zombie is 9 revolver body shots), so
  headshots and melee are worth more than the points they pay. Ammo for sale and the weapon carry limit are not decided
  here; see the open questions.

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

A grenade is never a sure kill: at 150 it kills a round-1 zombie (60) out to 5.6 m, a round-5 one (132) out to 2.7 m, and
no round-10 one (213) at all.

**Crippling.** The rules (`explosion` action) decide, never the world. A zombie that survives loses its legs and
becomes a crawler (once; one `zombie_crippled` event, speed times 0.35) when either:

- the blast damage on its **legs** adds up to a quarter of its full health (the blast was low and close), or
- the blast leaves it with **5% to 40%** of its health and a seeded roll (60%) says so: hurt badly but not dead.

So the ring just outside the kill radius makes crawlers, and in late rounds a grenade cripples everything near it
instead of killing it. The roll has its own stream in the rules' seed and is drawn only for a zombie in the band, so
every machine agrees. Gibs, decals and the fireball are client only and decide nothing.

## Open questions

- **Ammo as a shop item and the carry limit** (two or three weapons) need the shop and the player work; today a player
  may carry every weapon.
- **Friendly blast.** The flare's blast hurts zombies only; whether it hurts players (and whether a zombie on fire
  keeps burning) is a design call. A grenade hurts the thrower only (`player_blasted`); player health is not built yet,
  so that event is the seam for it.
- **Sound.** The shot sound request exists as a signal on the client; no audio is shipped yet.
- **Reload as a skill.** A magazine swap that rewards a timed second press, and cancelling a reload by sprinting, wait
  for the controller (#14).
- **Quick melee** on its own button, with the crowbar-style sweep and a fixed short cooldown, needs the controller
  too; the sweep and its damage are done.
- **Shooter position check.** The server trusts the muzzle and camera in a `fire` action; once the controller's
  position is authoritative on the server, the muzzle must be checked against it (a few metres) before a shot counts.
