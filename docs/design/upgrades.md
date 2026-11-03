# The re-cut and the hearty tonic

How a player's weapon and health grow during the night, so that the dead can grow too. The rules are in
`game/gameplay/rules/` (`ShopCounter`, `UpgradeTuning`, `PlayerHealth`), the weapon side in
`game/gameplay/weapons/` (`WeaponDef.upgraded`, `CombatServer`), every number in `default_tuning.tres`. Why the numbers
are these: [Weapon upgrades](../research/weapon-upgrade.md). Where the zombies' health comes from:
[Rounds, points and fuel](rounds.md).

The idea is studied from the genre's upgrade station and perks and made our own: the weapon is **re-cut** at the
projector, the way a film is re-cut, and health is a **tonic** from the soda fountain. The tonic is now one of six
[perks](perks.md). Nothing here is taken from another
game.

## The re-cut

Pay points to re-cut the weapon in your hand: it hits harder, holds more, and is filled.

| | |
| --- | --- |
| Item | `upgrade_weapon` (`ShopItem.Kind.UPGRADE`) |
| Price | **1,500**, and 1,500 more for each weapon you have already re-cut (1,500, then 3,000, then 4,500) |
| Damage | x1.75 on every hit: each pellet (a flare does no damage, so it gains nothing) |
| Magazine and reserve limit | x1.5, rounded up (the revolver holds 15 and carries 120, the Tommy gun 45 and 270) |
| Filled | the magazine and the reserve come back full at the new size, a reload in progress is dropped |
| Name | "Re-Cut " before the weapon's name ("Re-Cut Revolver") |
| Which weapons | the revolver, Tommy gun, shotgun, rifle and flare gun; once each. The crowbar has no magazine and is never re-cut |

What does not change: the fire interval, reload time, spread, falloff, zone multipliers and range. A re-cut weapon
is the same weapon, hitting harder, so the model, the sounds and the shop still know it by its id.

## The re-cut skin

A re-cut weapon **looks re-cut for as long as it is held**: the metal goes ink-blue and hard, a lattice of diamond
cells and traces lights up in cold cyan across the whole weapon (some cells burn and blink), a white-cyan pulse
runs down the barrel every couple of seconds, a rim of light with a violet fringe says "upgraded" from across a
room, and the whole thing breathes slowly. Every player sees it, in the player's own view, on the others' bodies and
in the menu's stage. The shader is `gameplay/weapons/fx/recut_skin.gdshader`, put on by `RecutSkin`, tuned in
`recut_style_default.tres` (`RecutStyle`); why it looks like this, what it costs and what the genre does:
[the re-cut skin](../research/recut-skin.md).

| | |
| --- | --- |
| Rule | the weapon in the hand wears the skin when its tier (`arms[weapon][2]` of the frame, the same number the ammo card reads) is above 0; a weapon swapped away, lost or bought again plain does not |
| Who sees it | every client, from the frame: the local body, the other players' bodies, a late joiner (it shows finished) |
| New weapon | none of the weapon's work: the shader stands in the surface's palette material (the same surface, no second pass), so a new model gets the skin with no texture, no scene and no code |
| Ignition | a weapon re-cut in the hand has the skin sweep on from the butt to the muzzle in 0.7 s (a white front, a flash); a weapon put in the hand already re-cut shows it finished |
| Cost | no draw call and no light more than the plain weapon: one lit opaque surface, one texture read (`tests/weapons/test_recut_skin.gd` pins it); the first use is paid in the warm-up |

**Who decides.** The server. The buyer presses use at the machine, the server finds the weapon in their hand and
sends the rules `RulesAction.buy(player, "upgrade_weapon", -1, weapon)`; the rules check (a weapon that can be
re-cut, not yet re-cut, enough points), charge, remember the weapon in `PlayerState.upgraded`, and answer
`purchase_made` with `detail {upgrade: weapon}`. The server turns that into `CombatAction.upgrade_weapon`, and the
combat server re-cuts its `WeaponState` and answers `weapon_upgraded` (`tier`, `display_name`, `ammo`, `reserve`,
`magazine`, `damage`). Refusals are `purchase_denied` with `NO_WEAPON` (nothing in hand the tuning allows),
`ALREADY_OWNED` or `NOT_ENOUGH_POINTS`.

**Wire.** The pull request that added this changed the wire in one commit: `RulesAction.buy` carries an optional
`weapon`, each player's snapshot carries `upgraded`, `GameRules.SNAPSHOT_VERSION` is 9, and `player_healed` has a
`tonic` reason.

## The hearty tonic

Tonics were shop entries that did nothing. The first with an effect is **hearty** (1,000 points, one per player):
**+50 most health** (100 to 150), and the same 50 health now, so it is never a wasted purchase. A player who is down
buys the room only and stands up to all of it. Getting up after a down restores the raised most. The effect is the
item's `health_bonus`. A player who goes down loses it again ([perks](perks.md#rules)); the other five tonics are the
other perks.

## The machines

| | Re-cut bench | Soda fountain |
| --- | --- | --- |
| Where | the projection booth ([the lot](map.md#shop-spots)) | the concession stand |
| Look | a cast-iron bench with two brass film reels on its tower, a sprocketed film strip along its front, a cradle under a press with a hot head, five ready lamps, a "RE-CUT / WHILE-U-WAIT" sign | a red and cream counter with a chrome band, a back bar of bottles, a tank of fizzing tonic, a tap with a lever, a neon heart over a "HEARTY" board |
| Prompt | "Re-cut: Revolver, damage x1.75, rounds x1.5, 1500 points"; "this weapon is already re-cut"; "nothing to re-cut in your hand" | "Hearty tonic, +50 most health, 1000 points"; "you have had yours" |
| On a purchase | the weapon lies on the cradle (plain), the reels spin up, the press drops and strikes at 0.8 s: a flash, a ring of light and sparks in the skin's cold blue, the head and the lamps and the bench's one light turn the same colour, and the weapon's skin sweeps on from butt to muzzle in 0.55 s; the lamps chase, a bell at 1.55 s; 2.4 s in all, the booth's amber back at the end | the lever pulls, the cork pops, the tumbler fills, the gulp at 0.55 s flashes the heart; 1.3 s in all |
| Sound | `buy_recut` (a recipe: motor, groan, blow, hiss, ratchet, bell; no ElevenLabs) | `buy_tonic` (the cork and the gulp) |
| HUD | the ammo card says "Re-Cut Revolver" and the bigger magazine and reserve; the feed says "had a weapon re-cut" | the health card reads the new most (150); the feed says "drank the hearty tonic" |

Every client plays the machine on the event (`weapon_upgraded` for the bench, `purchase_made` of the tonic for the
fountain), so everyone in the lot sees it. The offers are the server's (`MachineOffers`, the prompt kinds `recut`,
`recut_done`, `recut_none`, `tonic`, `tonic_owned`); the card's words are `MachinePrompts`; `MachineView` starts the
machines; a late joiner sees idle machines and names the re-cut weapon from the frame's `arms` (`[ammo, reserve,
tier]`, the second wire change of #281).

## What it asks of the rest

- **Zombie health compounds at 15% a round** after round 8 (7% when this page was written, 5% before,
  [#745](rounds.md#the-headshot-retune-745)), the genre's own order of magnitude, because weapons now grow in a step.
  [The table](rounds.md#the-tuning-table) has the numbers.
- **The balance gate** plays the modelled players buying both ([balance simulator](../research/balance-simulator.md)):
  an average player saves for the re-cut after the wall weapons and the crane, re-cuts the weapon that kills most,
  then buys the tonic. The gate's ranges did not move, and a test fails the gate when the same shopping changes
  nothing.
- **The places** are the lot's, in [the map](map.md#shop-spots): the re-cut in the projection booth and the tonics at the
  concession's soda fountain and, until the perks of #687 give it its own, a second fountain in the ticket plaza behind
  the road door.

## The re-cut plan for seventeen weapons (#785)

**Planned, not built** (the build is [#794](https://github.com/Ryubara/deadnight/issues/794)). The research
([the roster](../research/weapon-roster.md#the-upgrade-station-what-the-genre-does-and-what-ours-does)) found no reason
to change the re-cut: it stays **1,500 points (+1,500 per weapon already re-cut), x1.75 damage, x1.5 magazine and
reserve limit, filled, once a weapon**. What the plan adds is which weapons it goes on, what each one becomes, and the
**elements**.

- **Fourteen of the seventeen are re-cut**: the five that are now plus the nine new ones. `UpgradeTuning.weapons` (the list
  `UpgradeTuning.allows` reads) gains `mp5`, `ppsh`, `m4a1`, `m249`, `fifty_cal`, `pump_870`, `dual_pistols`, `ray_gun`
  and `freeze_gun`; without them the bench refuses them and the simulator never re-cuts them (the first run of the
  research found it). The crowbar, the baseball bat and the fire axe have no magazine and are **not** re-cut, as
  today; the quick melee is no weapon.
- **The special effects go only to the weakest guns**, the maintainer's rule, and the genre's own (its start pistol, the
  weakest weapon, is the one that gets explosive rounds, and nothing stronger does). "The weakest" is read off the kill
  rate on round 15 with reloads and the head-shot rate there, after the re-cut ([the table](weapons.md#where-each-stands-against-the-others)):
  the flare gun (no damage at all), the revolver, the pump 870 and the dual pistols are the four. **Every other weapon gets
  the numbers only.**
- **One element each, four in all**, no weapon gets two, a re-cut weapon shows its element (a tint of the
  flash and the hit, the name "Re-Cut ..." as today) and the HUD card names it.

### The four elements

| Element | On | What a hit does (numbers on the re-cut hit `H`) | Why it is on this weapon |
| --- | --- | --- | --- |
| **Explosive rounds** | Revolver | every hit that lands bursts a **2.0 m blast** for 50% of `H` at the centre sliding to 25% at the edge, on the other zombies only (the one hit takes the hit alone, as the flare's burst does); **the interval goes from 0.28 s to 0.40 s** (the genre's explosive pistol fires slower); the shooter and teammates take nothing | the start weapon, the weakest firearm (57 a second on round 15): the genre's own explosive start pistol; the slower rate is its price, so the best re-cut in the simulator stays inside it |
| **Shock** | Dual pistols | a hit **arcs to up to two other zombies within 3 m** for 50% of `H` each (an instant, one arc, no chain), shown as a blue-white line; the arc counts as a hit for pay | a box pair of small hits (29.75 re-cut): the arc turns two guns' rate into a crowd's |
| **Fire** | Pump 870 | a hit sets the zombie **burning: 30 damage a second for 3 s** (90 in all), not stacking (a new hit restarts the 3 s); a zombie that burns dies on its own clock and pays its killer | the cheapest wall and the weakest late (84 a second on round 15): the 90 of burn finishes what a 231 shell leaves standing |
| **Burning ground** | Flare gun | the burst leaves a **fire patch of 3 m radius** for the lure's whole time (`lure_seconds`, 8 s), **25 damage a second** to every zombie in it; the lure keeps the dead inside the fire | the flare does no damage at all (#439) and is the weakest weapon; the re-cut is its first reason to carry it into a late round |

Elements are statuses the status system of [#788](https://github.com/Ryubara/deadnight/issues/788) already needs for the
freeze: **burning** (a damage over time with a duration) is the one more it adds; the **blast** and the **arc** are
instant extra hits made by the combat server on the hit's own event; the burning ground is a lure-like area
(`lure_started` already carries the point, radius and seconds). None needs a new rules action: every damage is one more
`hit` for the zombie it hits, so the pay and the rounds' health stay the rules'.

### What each weapon becomes

The re-cut hit, magazine and reserve (limit in brackets), and the shots to kill a round-15 zombie (282 health) on the
body and on the head (all the pellets of a shell count as one pull). The first eight rows are the weapons as shipped; the
simulator's worth of each is in [the research](../research/weapon-roster.md#what-a-weapon-is-worth-average-solo-150-nights-seed-1).

| Weapon | Re-cut hit | Magazine | Reserve (limit) | Round 15, body / head | Element or special |
| --- | ---: | ---: | --- | ---: | --- |
| Revolver | 42 | 15 | 60 (120) | 7 / 3 | **explosive rounds** (0.40 s) |
| Tommy gun | 24.5 | 45 | 180 (270) | 12 / 6 | numbers only |
| Double-barrel | 38.5 x 8 | 3 | 24 (48) | 1 / 1 | numbers only: it is a close one-pull kill already |
| Hunting rifle | 166 | 12 | 60 (120) | 2 / 1 | numbers only |
| Flare gun | 0 | 2 | 9 (18) | none | **burning ground**; its damage multiplier stays nothing |
| Crowbar, baseball bat, fire axe | 45, 60, 150 | none | none | | **not re-cut**: no magazine to grow (today's rule) |
| MP5 | 26.25 | 45 | 180 (270) | 11 / 6 | numbers only |
| PPSh | 17.5 | 75 | 150 (300) | 17 / 11 | numbers only: the drum is the re-cut |
| M4A1 | 35 | 45 | 135 (225) | 9 / 5 | numbers only |
| M249 | 26.25 | 150 | 225 (375) | 11 / 7 | numbers only: the long belt is the re-cut; the reload stays 5.0 s |
| Fifty cal | 385 | 8 | 30 (60) | 1 / 1 | numbers only: a body kill to round 17 and a head kill to 22 |
| Pump 870 | 38.5 x 6 | 9 | 63 (99) | 2 / 2 | **fire** |
| Dual pistols | 29.75 | 36 | 108 (180) | 10 / 5 | **shock** |
| Ray gun | 525, blast 280 | 15 | 60 (90) | 1 / 1 | numbers only: a body kill to round 19, a head kill to 22; the blast's 3.0 m does not grow |
| Freeze gun | 52.5 | 9 | 36 (54) | none | numbers only, **and the freeze's one-bolt band grows from 10 rounds to 20** and the bloom from 2.2 m to 2.8 m (a wonder weapon's "more devastating effect", never an element) |

- **Wonder weapons get no element**: the ray gun and the freeze gun are the strongest weapons and the rule keeps
  elements for the weakest. Their re-cut is numbers, as the genre's (doubled damage, a bigger magazine).
- **The numbers of the new weapons are re-cut like the old**: `WeaponDef.upgraded` multiplies the damage, the blast, the
  magazine and the reserve of any definition, so the nine need no code for it; the elements are fields of the
  definition (an `element`, its numbers) that `upgraded` switches on and the interval change of the revolver is one of
  them.
- **Worth keeping, measured**: in the simulator a re-cut MP5, M4A1 or M249 is worth 14.5 rounds to the average solo
  player against 12.4 for the re-cut revolver, the ray gun 16.3, the dual pistols 13.8 and the PPSh 13.1
  ([the table](../research/weapon-roster.md#what-a-weapon-is-worth-average-solo-150-nights-seed-1)). The simulator
  does not model the elements; a weapon whose element is not measurable is held by the numbers above, not by the model.
- **The cost does not change** with the roster: 1,500 for the first, then +1,500 each. A weapon given up loses its re-cut
  (`recuts_lost`) and a fresh copy can be re-cut again at the stepped price.
