class_name HealthTuning
extends Resource
## How hard a player is to kill, as the rules see it: the health bar, and how fast it mends. A
## blow is whatever damage the world sends in `RulesAction.blow`; the rules decide the rest.

@export_range(1.0, 1000.0, 1.0, "or_greater", "suffix:hp") var max_health: float = 100.0
## Seconds without a blow before health comes back.
@export_range(0.0, 100.0, 0.05, "or_greater", "suffix:s") var regen_delay: float = 5.0
## Health a second once it has started to come back.
@export_range(0.0, 200.0, 0.5, "or_greater", "suffix:hp/s") var regen_per_second: float = 25.0
## Seconds a teammate holds the revive on a downed player before they get up (the balance
## simulator reads the same number).
@export_range(0.5, 20.0, 0.1, "or_greater", "suffix:s") var revive_seconds: float = 3.5
## The share of `max_health` a player has when a teammate gets them up. Getting up at the end of a
## round gives all of it.
@export_range(0.0, 1.0, 0.05) var revive_fraction: float = 0.5
