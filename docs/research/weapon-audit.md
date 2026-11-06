# The weapon audit

What was learnt auditing every weapon against its class (#972). The result is on
[the weapons page](../design/weapons.md#the-audit-972); this page keeps how it was measured, what the balance gate
did and what to do when a weapon is added.

## How a weapon is measured

`game/tests/weapons/weapon_audit.gd` (`WeaponAudit`) is one run of the real damage path: a night with one walker of a
round on the lot, the weapon in the shooter's hands through `CombatAction.give_weapon`, the shooter's eye at the real
eye height (`NightTuning.eye_height`), a ray to a height on the figure, the fitted hit zones, the combat server and the
rules' health. It returns the trigger pulls and the seconds to kill and the zones the pulls met. Never the table: the
lessons on the start pistol and the melee head zone were both a table that nobody had checked against this.

- **The weapon never runs dry** in the probe (`reserve = 99999`): rounds are a class target of their own (the magazine
  band), not part of a time to kill. It does reload when the magazine is empty, as a player would.
- **The server is made before the zombies spawn.** It learns of a zombie from the rules' spawn event; one made later
  tracks none, and every shot passes through the lot (the line-up test hit nobody until this was fixed).
- **A scatter weapon is the median of three seeds**, the rest are exact.
- **Rounds 15 and 20 use the re-cut weapon** (`CombatAction.upgrade_weapon`), since the health curve outgrows a shipped
  one by design.
- A chest-high aim from the eye lands on the body, a head-high aim on the head, a leg-high aim on the limb zone, at
  4 m; the shotgun's pellets spread, so its zone is whatever they land on.

## What the balance gate did

The gate (60 nights, seed 4000, six cells: weak solo, average 1, 2, 4 and 8, strong solo; the medians in that order),
before from a separate checkout of `main` at `4802a6f3` and after from the audit's branch on the same `main`:

| | Medians | Passes |
| --- | --- | --- |
| `main` | 4 / 10 / 13 / 15 / 17 / 14 | yes |
| After the audit | 5 / 10 / 15 / 16 / 17 / 17 | yes (`test_balance_targets`) |

The box's guns were raised (the revolver, dual pistols, MP5, PPSh, M249, the pump) and the two strongest melee weapons
lowered a little, so the simulated players, who pick by worth, do a little better with the crane's prizes: the weak
solo median rises a round, the average two- and four-player and the strong solo medians by two, one and three, inside
the ranges. A first
try that cut the wall's Tommy gun and double-barrel instead (the other way to meet the ladder rule), measured on the
`main` before the House Pistol, took the average solo median from 11 to 10 and the two-player median from 14 to 13,
because the simulated players buy the wall's guns first: the box's guns were raised instead.

## When a weapon is added

1. Give its `defs/<id>.tres` a **class** (`weapon_class`), a **wall tier** and a **crane weight**: the Source and
   Class groups of the inspector.
2. Run `test_weapon_class_bands.gd`, `test_weapon_ladder.gd` and `test_penetration_line.gd`. A failure names the weapon,
   the round and the band ("Reel Gun (SMGs) round 15, re-cut: 0.78 s to kill, the class takes 0.80 to 1.30 (too
   strong)"). Retune the weapon or change its class; widen a band only with the reason on the weapons page.
3. Re-run the balance gate and put the medians in the pull request.
