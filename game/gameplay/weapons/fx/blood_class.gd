class_name BloodClass
extends Resource
## How one kind of hit bleeds: the splash a zombie shows at the wound and the marks it leaves on the
## ground and the wall behind. Five kinds are tuned in `blood_tuning_default.tres` (a bullet, a
## shotgun's pellets, a rifle, a melee blow, a blast). Sizes are in metres, angles in degrees.

## Drops flung from the wound (the shader draws at most `BloodFx.MAX_DROPS`).
@export_range(1, 16, 1) var drops: int = 8
## Drops added for each further pellet or hit of the same shot (a shotgun that lands six pellets).
@export_range(0.0, 4.0, 0.1) var drops_per_pellet: float = 0.0
## How far the farthest drop flies, and so half the width of the splash quad.
@export_range(0.1, 2.0, 0.01, "suffix:m") var reach: float = 0.5
## Half the angle the drops fan across around the way the shot went.
@export_range(5.0, 180.0, 1.0, "suffix:deg") var cone_deg: float = 40.0
## Diameter of the biggest drop.
@export_range(0.005, 0.3, 0.005, "suffix:m") var drop_size: float = 0.05
## 0 is round drops, 1 is long streaks along their flight.
@export_range(0.0, 1.0, 0.01) var streak: float = 0.5
## Diameter of the blot at the wound.
@export_range(0.0, 0.6, 0.005, "suffix:m") var splat_size: float = 0.14
## 0 is no smear, 1 a long tapering smear along the blow (a melee weapon drags it).
@export_range(0.0, 1.0, 0.01) var smear: float = 0.0
## The share of the drops flung back the way the shot came from (the entry spray).
@export_range(0.0, 1.0, 0.01) var back: float = 0.12
## Seconds the splash lives.
@export_range(0.05, 2.0, 0.01, "suffix:s") var seconds: float = 0.4
## Marks left on the ground near the zombie, and on a wall behind it.
@export_range(0, 4, 1) var ground_marks: int = 1
@export_range(0, 2, 1) var wall_marks: int = 1
## Diameter of a ground mark.
@export_range(0.05, 1.5, 0.01, "suffix:m") var mark_size: float = 0.4
