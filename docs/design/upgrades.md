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
| On a purchase | the weapon lies on the cradle, the reels spin up, the press drops and strikes at 0.8 s with a flash and sparks, the weapon glows brass, the lamps chase, a bell at 1.55 s; 2.4 s in all | the lever pulls, the cork pops, the tumbler fills, the gulp at 0.55 s flashes the heart; 1.3 s in all |
| Sound | `buy_recut` (a recipe: motor, groan, blow, hiss, ratchet, bell; no ElevenLabs) | `buy_tonic` (the cork and the gulp) |
| HUD | the ammo card says "Re-Cut Revolver" and the bigger magazine and reserve; the feed says "had a weapon re-cut" | the health card reads the new most (150); the feed says "drank the hearty tonic" |

Every client plays the machine on the event (`weapon_upgraded` for the bench, `purchase_made` of the tonic for the
fountain), so everyone in the lot sees it. The offers are the server's (`MachineOffers`, the prompt kinds `recut`,
`recut_done`, `recut_none`, `tonic`, `tonic_owned`); the card's words are `MachinePrompts`; `MachineView` starts the
machines; a late joiner sees idle machines and names the re-cut weapon from the frame's `arms` (`[ammo, reserve,
tier]`, the second wire change of #281).

## What it asks of the rest

- **Zombie health compounds at 7% a round** after round 8 (it was 5%), the genre's own order of magnitude, because
  weapons now grow in a step. [The table](rounds.md#the-tuning-table) has the numbers.
- **The balance gate** plays the modelled players buying both ([balance simulator](../research/balance-simulator.md)):
  an average player saves for the re-cut after the wall weapons and the crane, re-cuts the weapon that kills most,
  then buys the tonic. The gate's ranges did not move, and a test fails the gate when the same shopping changes
  nothing.
- **The places** are the lot's, in [the map](map.md#shop-spots): the re-cut in the projection booth and the tonics at the
  concession's soda fountain.
