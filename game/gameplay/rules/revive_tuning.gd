class_name ReviveTuning
extends Resource
## Being downed and being pulled back up, as the rules see it: how long a downed player has, how
## long a teammate holds Use to get them up, and what getting up gives. Designers edit these in
## `default_tuning.tres` (docs/design/revive.md); no code holds the numbers.

## Seconds a downed player has before they are dead (until the round ends), if nobody holds the
## revive.
@export_range(5.0, 300.0, 0.5, "suffix:s") var bleed_out_seconds: float = 45.0
## Seconds a teammate holds Use beside the body to pull the player up.
@export_range(0.5, 20.0, 0.1, "suffix:s") var revive_seconds: float = 3.5
## How near the reviver stands to the body, metres; further and the hold breaks.
@export_range(0.5, 5.0, 0.05, "suffix:m") var reach: float = 2.0
## The share of their most health a revived player gets up with (a round's end gives all of it).
@export_range(0.05, 1.0, 0.05) var health_fraction: float = 0.5
## Points the reviver is paid for a revive. A maintainer decision (docs/design/revive.md): 0 for
## now.
@export_range(0, 1000, 5) var reviver_points: int = 0
## The bleed-out clock stands still while someone holds the revive, so a revive that began never
## ends in a death by a hair.
@export var bleed_stops_while_held: bool = true
