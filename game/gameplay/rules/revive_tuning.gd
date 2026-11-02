class_name ReviveTuning
extends Resource
## Being downed, as the rules see it: how long a downed player has before they bleed out, and what a
## revive pays. How long the hold takes and what health it gives are `HealthTuning.revive_seconds`
## and `revive_fraction`, how near the reviver stands `NightTuning.revive_reach`. Designers edit
## these in `default_tuning.tres` (docs/design/revive.md); no code holds the numbers.

## Seconds a downed player has before they are dead (until the round ends), if nobody holds the
## revive.
@export_range(5.0, 300.0, 0.5, "suffix:s") var bleed_out_seconds: float = 45.0
## Points the reviver is paid for a revive. A maintainer decision (docs/design/revive.md): 0 for
## now.
@export_range(0, 1000, 5) var reviver_points: int = 0
## The bleed-out clock stands still while someone holds the revive, so a revive that began never
## ends in a death by a hair.
@export var bleed_stops_while_held: bool = true
