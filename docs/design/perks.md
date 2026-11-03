# Perks

Six drinks that change what a player can do for the rest of the night, sold from machines on the lot. Their effects
follow the genre's classic perks; their names, machines, drinks, boards and sounds are ours, in the drive-in's style.
The rules are in `game/gameplay/rules/` (`PerkTuning`, `PerkEffects`, `PerkPlay`, `RevivePlay`, `WeaponCarry`), the
combat side in `game/gameplay/weapons/` (`CombatServer`), the shock in `NightServer`, every number in
`default_tuning.tres` (the `perks` block and the six tonic items). A perk is a **tonic** (`ShopItem.Kind.TONIC` with an
`effect`): the hearty tonic was the first, built for [the re-cut and the tonic](upgrades.md#the-hearty-tonic).

## The six

The name says the job: each stays close in meaning to the genre perk it stands in for (the middle column), and the
machine's board says it again in words.

| Our name (board) | The genre's role | What it does | Machine, and where |
| --- | --- | --- | --- |
| **Hearty Health Tonic** (`tonic_hearty`) | more health | +50 most health (100 to 150) and the same 50 now | the soda fountain, the concession stand |
| **Double Shot Soda** (`tonic_double_shot`) | faster fire | the wait between shots is 1/1.33 of the weapon's | a red cooler with two glowing bullets, the generator yard |
| **Quick Load Cola** (`tonic_quick_load`) | faster reload | a reload takes half the time | a teal cooler with a spinning revolver drum, the projection booth |
| **Third Holster Ale** (`tonic_third_holster`) | a third weapon | carry three weapons, not two | a purple cooler with three racked guns, the ticket plaza (behind the road's door) |
| **Swift Rescue Lemonade** (`tonic_swift_rescue`) | faster revive, and a solo self-revive | holds a teammate's revive in half the time; with nobody on their feet to do it, gets the holder up alone | a green cooler with a heartbeat cross, the midway |
| **Reload Shock Orange** (`tonic_reload_shock`) | a shock on reload | a reload gives off a shock that hurts, holds and shoves the dead within 4 m | an orange cooler with an arc between two electrodes, the back lot |

Prices, the per-player limit and what going down costs are [from the simulator](../research/perks.md#numbers).

## What a player sees at a machine

Within reach (`NightTuning.use_reach`, 3.2 m) of a machine the prompt card shows **the name, the price and one plain
line** of what it does, and a press of use buys it, the same press as a door ([the card](hud.md)):

| Machine | Card |
| --- | --- |
| Soda fountain | Hearty Health Tonic, 1000 points, +50 MOST HEALTH |
| Double Shot | Double Shot Soda, 3000 points, FIRES 33% FASTER |
| Quick Load | Quick Load Cola, price, RELOADS 100% FASTER |
| Third Holster | Third Holster Ale, price, CARRY 3 WEAPONS INSTEAD OF 2 |
| Swift Rescue | Swift Rescue Lemonade, price, REVIVE TEAMMATES 100% FASTER. GETS YOU UP ALONE, 3 TIMES A NIGHT |
| Reload Shock | Reload Shock Orange, price, RELOADING SHOCKS THE DEAD WITHIN 4.0 M |

The numbers on the card are the tuning's (`MachinePrompts.blurb`), so a retune changes the card too. A player who has
the perk reads YOU HAVE HAD YOURS, one at the limit reads YOU CARRY 4 TONICS, THE MOST, and neither is charged. The feed
says "drank the Double Shot Soda" for everyone to see; each machine also plays its pour (a bottle drops into the tray,
the cap pops, the emblem flashes) on `purchase_made`, so every client sees it.

## Rules

**Who decides.** The server. `purchase_made` is the rules' answer to a buy; `PerkEffects` reads a player's tonics and
answers every question about an effect, so the combat server, the revive channel, the rules and the balance simulator
mean the same thing by each.

- **Faster fire** scales the cooldown the combat server sets after a shot (`WeaponState.fire`); a melee weapon is
  swung at its own pace. The server shoots on whole 1/60 s ticks, so 1.33 shows as 1.2 to 1.33 in a count of shots
  (the Tommy gun fired 24 and 30 shots in two seconds, without and with the perk).
- **Faster reload** scales the reload; `reload_started.seconds` is the scaled time, so the HUD, the soldier's clip
  and the sounds follow with no change.
- **A third weapon** raises the carry limit (`PerkEffects.carry_limit`, `WeaponCarry`, `CombatServer`) by
  `PerkTuning.extra_weapons`. The third weapon is the slot **3** of the weapon slots
  ([#682](https://github.com/Ryubara/deadnight/issues/682)): the carry order is the order the weapons were taken,
  the third is the last. It is lost with the perk (below).
- **Faster revive** is the reviver's: `ReviveChannel` holds for `PerkEffects.revive_seconds(reviver)`, so the downed
  player's own perks change nothing.
- **A solo self-revive** (`RevivePlay.can_self_revive`, [the revive rules, #505](revive.md)): a downed holder with a use
  left and **no teammate on their feet** counts `self_revive_seconds` (4 s) and gets up with the usual half health,
  `self_revives` of `self_revive_uses` (3) a night. The night does not end meanwhile (`_check_game_over` waits for it),
  their bleed-out clock stands still, and they lose none of their perks. A lone player with bots on their feet is not
  alone: the bots can raise them. `self_revive_started` and a `player_revived` with `self` tell the clients.
- **A shock on reload** (`NightServer._shock`): when a reload starts, every living zombie within `shock_radius` takes
  `shock_damage` as a blast (the rules pay and kill, `ExplosionPlay`), is held for `shock_stun_seconds` and shoved
  `shock_push` m/s. `shock_cooldown` apart, so a reload cancelled and started again is not a free shock.
  `shock_burst` carries where, how far and who was hit.

**The limit and the loss.** A player carries at most `economy.max_tonics`; a tonic is bought once. A player who
**goes down loses** what `perks.lost_on_down` says (`PerkPlay`): the health the hearty tonic gave goes with it and
the weapon in the third slot is given up (`perks_lost`, the weapon leaves as a `weapon_replaced` with no new
weapon). A self-revive loses nothing. The loss is the genre's; whether it is all, the last or none is [a number of
the simulator](../research/perks.md#numbers).

## The look

Each machine is a 1950s drink cooler built from primitives (`PerkMachine`, `MachineParts`, no asset): a glass front of
bottles in the perk's drink colour, a coin slot, a dispense tray, a lit board with the name and what it does in words
(the same words as the table above), and an emblem over it that does one small thing while it waits (the bullets take
turns, the drum turns, the guns light one, two, three, the cross beats like a heart, the arc jumps between its
electrodes). They add **no light** (a Compatibility mesh takes eight lights at most): the glow is emission. The soda
fountain keeps its own design and says HEARTY HEALTH.

### The shock shader

`gameplay/weapons/fx/shock_arc.gdshader`, one flat quad on the ground round the player (`ShockEffect`): a ring that
runs out to the shock's radius, seven jagged bolts from the player to the ring and a flash at the middle, in two
flat colours (an electric blue rim round a pale core), hard edges anti-aliased on the edge only, like the muzzle
flash. It is unshaded and additive, uses no screen or depth texture and no dynamic loop, and its hash is the
sine-free one the menu shader uses, so it runs in the Compatibility renderer and in a browser alike. The warm-up
draws it still in frames of its own, so the first shock of a night does not stop the page. Sound: `shock_zap` (a
crackle over a mains buzz, a recipe, no ElevenLabs).

## Which perk the road area gets

[#686](https://github.com/Ryubara/deadnight/issues/686) closed the unfinished road and gave the ticket plaza behind
the road's door one perk machine, left as a second soda fountain until these perks landed. **The Third Holster** takes
it: it is the dearest perk and the road's door (2,000) the dearest door, a third weapon is the one perk worth walking to
the end of the lot for, and it changes how the whole carry works, so it is the one a team plans a night around. The
machine stands against the plaza's south wall over the area's own hidden block (`Road/PerkMachine`).

## What it asks of the rest

- **The bots** buy tonics they lack, up to the limit, and buy them again after a down (`BotEconomy`, the frame's `perks`
  bits); their lists are the simulator's.
- **The balance gate** plays the modelled players buying them ([research](../research/perks.md)).
- **The snapshot** is version 14 (`self_revives`, `self_revive_left`).
- **The HUD** shows the perks had as [badges beside the health card](hud.md#the-perk-badges) (#707), read from the frame's
  `perks` bits, gone with a down that takes them; the DOWN card and the ring over the view say `GETTING YOURSELF UP` and
  count the seconds while the revive perk gets the holder up alone. The card at the machine and the feed ("LOST THEIR
  PERKS", "IS GETTING THEMSELVES UP") say the same in words.
