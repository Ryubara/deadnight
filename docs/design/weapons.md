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

## Open questions

- **Ammo as a shop item and the carry limit** (two or three weapons) need the shop and the player work; today a player
  may carry every weapon.
- **Friendly blast.** The flare's blast hurts zombies only; whether it hurts players (and whether a zombie on fire
  keeps burning) is a design call.
- **Sound.** The shot sound request exists as a signal on the client; no audio is shipped yet.
- **Reload as a skill.** A magazine swap that rewards a timed second press, and cancelling a reload by sprinting, wait
  for the controller (#14).
- **Quick melee** on its own button, with the crowbar-style sweep and a fixed short cooldown, needs the controller
  too; the sweep and its damage are done.
- **Shooter position check.** The server trusts the muzzle and camera in a `fire` action; once the controller's
  position is authoritative on the server, the muzzle must be checked against it (a few metres) before a shot counts.
