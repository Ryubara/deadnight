class_name DeadContactTuning
extends Resource
## How the player meets the dead (#914): the dead are not physics bodies, so the body is stopped by
## them in the player simulation (`DeadBlock`), against circles read from the zombies' positions
## (`DeadField`), and the server lets a sustained push move a zombie aside (`DeadShove`). The
## shipped values are in `dead_contact_tuning_default.tres`; `DeadContactTuning.shipped()` is how
## the night and the tests read it. The body half (`Body`) is read on every machine that moves a
## player; the `Shove` half only by the server.

## How a push moves a zombie once it has begun to yield (`DeadShove`).
enum Policy {
	## Nothing yields until the push has held `hold_seconds`; then the zombie goes at `shove_speed`.
	TIMED,
	## The zombie goes at once, at `wade_share` of the speed the person pushes at.
	WADE,
	## Nothing for `hold_seconds`; then the zombie goes faster the longer the push holds, from
	## `ramp_from` to `ramp_to` over `ramp_seconds`, and slower with the crowd behind it.
	RAMP,
}

const SHIPPED_PATH := "res://gameplay/player/dead_contact_tuning_default.tres"

@export_group("Body")
## Whether the dead stop the player at all (off: the player walks through them, as before #914).
@export var enabled: bool = true
## Metres from a zombie's feet to its edge. The player's own radius is added to it.
@export_range(0.1, 1.0, 0.01, "suffix:m") var radius: float = 0.4
## A player whose feet are this far above a zombie's feet is over its head (a car roof): no contact.
@export_range(0.5, 3.0, 0.05, "suffix:m") var reach_above: float = 1.4
## A zombie whose feet are this far above the player's feet is on the ramp over it: no contact.
@export_range(0.5, 3.0, 0.05, "suffix:m") var reach_below: float = 1.0
## Zombies this near (metres) to the body are looked at in a tick; a tick moves a body 0.1 m.
@export_range(1.0, 8.0, 0.1, "suffix:m") var near_range: float = 3.0
## A player this close (metres) to the edge of a zombie is touching it.
@export_range(0.0, 0.2, 0.005, "suffix:m") var touch_gap: float = 0.03
## Metres a second of the stick into a zombie that counts as pushing on it.
@export_range(0.0, 3.0, 0.05, "suffix:m/s") var press_min: float = 0.6

@export_group("Shove")
@export var policy: Policy = Policy.TIMED
## Seconds of unbroken push before a zombie begins to yield (TIMED, RAMP).
@export_range(0.0, 5.0, 0.05, "suffix:s") var hold_seconds: float = 0.6
## Metres a second a yielding zombie goes at (TIMED).
@export_range(0.0, 6.0, 0.05, "suffix:m/s") var shove_speed: float = 1.0
## The share of the speed the person pushes at that the zombie yields at (WADE).
@export_range(0.0, 1.0, 0.01) var wade_share: float = 0.35
## RAMP: the speed a zombie begins to yield at, the speed it reaches, and the seconds it takes.
@export_range(0.0, 6.0, 0.05, "suffix:m/s") var ramp_from: float = 0.3
@export_range(0.0, 6.0, 0.05, "suffix:m/s") var ramp_to: float = 2.0
@export_range(0.05, 5.0, 0.05, "suffix:s") var ramp_seconds: float = 1.5
## RAMP: each zombie within `crowd_radius` of the one pushed takes `crowd_drag` off its yield, as a
## fraction of it before (1 / (1 + drag * neighbours)).
@export_range(0.0, 2.0, 0.05) var crowd_drag: float = 0.4
@export_range(0.3, 2.0, 0.05, "suffix:m") var crowd_radius: float = 1.0
## The share of the yield a boss gives.
@export_range(0.0, 1.0, 0.05) var boss_share: float = 0.3
## Seconds of push lost for each second the push is let go (1 forgets it as fast as it built).
@export_range(0.0, 10.0, 0.1) var release_rate: float = 2.0
## How much of a yield goes sideways: 0 straight away from the body (the zombie goes ahead of the
## player, who follows it), 1 across the player's way (it rolls out of it). The side is the one the
## zombie already leans to, or its id's when it is dead ahead.
@export_range(0.0, 1.0, 0.05) var lateral: float = 0.8
## The fastest a zombie may be nudged, whatever the person pushes at.
@export_range(0.5, 8.0, 0.1, "suffix:m/s") var yield_cap: float = 3.0


## A private copy of the shipped table: a test or a measurement may change it without touching the
## file or another night.
static func shipped() -> DeadContactTuning:
	return (load(SHIPPED_PATH) as DeadContactTuning).duplicate(true) as DeadContactTuning
