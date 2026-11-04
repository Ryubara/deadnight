class_name ExplosiveTuning
extends Resource
## Grenades as the rules see them: how many a player carries, what a blast pays, and when a blast
## cripples a zombie into a crawler. The blast's own numbers (radius, damage, fuse) are the grenade
## definition's (`GrenadeDef`); the rules never see geometry, only the damage each zombie took.

@export_group("Carrying")
## Grenades a player starts the night with.
@export_range(0, 20, 1, "or_greater") var start_grenades: int = 2
## Every round start tops a player up to at least this many.
@export_range(0, 20, 1, "or_greater") var refill_to: int = 3
## The most a player can carry, shop included.
@export_range(0, 20, 1, "or_greater") var max_grenades: int = 5

@export_group("Points")
## The blast that kills pays this, not the gun kill: a grenade clears crowds, so it pays less each.
@export_range(0, 1000, 5, "or_greater", "suffix:pts") var explosion_kill: int = 40

@export_group("Crippling")
## Blast damage that landed on the legs, as a fraction of the zombie's full health, past which the
## legs go (the zombie lives on as a crawler).
@export_range(0.0, 2.0) var leg_fraction: float = 0.25
## A zombie a blast leaves alive with health between these fractions of its full health may lose
## its legs too: "hurt badly but not dead".
@export_range(0.0, 1.0) var band_low: float = 0.05
@export_range(0.0, 1.0) var band_high: float = 0.4
## The chance (seeded, so every machine agrees) that a zombie in that band is crippled.
@export_range(0.0, 1.0) var band_chance: float = 0.6
## A crawler moves at this fraction of the speed its walker had.
@export_range(0.05, 1.0) var crawler_speed_fraction: float = 0.35
