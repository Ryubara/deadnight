class_name PerkTuning
extends Resource
## What each perk does and what going down costs (`docs/design/perks.md`). A perk is a tonic the
## shop sells (`ShopItem.Kind.TONIC` with an `effect`); its price is the item's, its health the
## item's `health_bonus`, everything else is here. The balance simulator reads the same numbers, so
## a retune is tried there first (`docs/research/perks.md`).

## What a player who goes down loses of the perks they have had.
enum Loss { NONE, LAST, ALL }

@export_group("The drink")
## How long a perk takes to drink (the clip `Drink_Perk` is played over it): the price is paid
## at the machine and the perk is had when the drink ends. Meanwhile the hands are full: no
## shot, reload, swap, blow, throw, repair, revive or purchase. A blow does not stop it; going
## down spills it (the perk is not had and the price is not given back). 0 gives the perk at
## once.
@export_range(0.0, 10.0, 0.1, "suffix:s") var drink_seconds: float = 2.5

@export_group("Fire and reload")
## Faster fire: the wait between shots is divided by this (1.33 is a quarter shorter). A melee
## weapon is swung at its own pace.
@export_range(1.0, 4.0, 0.01, "suffix:x") var fire_rate_multiplier: float = 1.33
## Faster reload: the reload takes this share of its time (0.5 is twice as fast).
@export_range(0.1, 1.0, 0.05, "suffix:x") var reload_time_scale: float = 0.5

@export_group("Carry")
## A third weapon: the weapons more a player can carry (`WeaponCatalog.CARRY_LIMIT` is the base).
@export_range(0, 3, 1) var extra_weapons: int = 1

@export_group("Revive")
## A faster revive: the reviver holds for this share of `HealthTuning.revive_seconds`.
@export_range(0.1, 1.0, 0.05, "suffix:x") var revive_time_scale: float = 0.5
## A solo self-revive: a player with the perk, down with no teammate on their feet, gets themselves
## up after this long.
@export_range(0.5, 30.0, 0.5, "suffix:s") var self_revive_seconds: float = 4.0
## How many times a night the perk gets its holder up alone; the last use is the end of the perk.
@export_range(0, 10, 1) var self_revive_uses: int = 3

@export_group("Shock")
## The shock a reload gives off around the player: how far it reaches, what it does to each dead
## thing in reach, how long it holds them, how hard it shoves them, and the wait before it can fire
## again (a reload cancelled and started again is not a free shock).
@export_range(0.5, 20.0, 0.1, "suffix:m") var shock_radius: float = 4.0
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:hp") var shock_damage: float = 140.0
@export_range(0.0, 10.0, 0.05, "suffix:s") var shock_stun_seconds: float = 1.6
@export_range(0.0, 20.0, 0.5, "suffix:m/s") var shock_push: float = 5.0
@export_range(0.0, 60.0, 0.5, "suffix:s") var shock_cooldown: float = 4.0

@export_group("Going down")
## What a player who goes down loses (a self-revive loses nothing).
@export var lost_on_down: Loss = Loss.ALL
