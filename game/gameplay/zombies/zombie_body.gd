class_name ZombieBody
extends RefCounted
## One zombie as plain data. It has no health: the rules own that (a zombie lives until the rules
## say it is removed). Everything a client needs to draw it is `view_entry()`.

enum Mode { EMERGING, CHASE, ATTACK, STAGGER, DYING }

var id: int = 0
## What it is and how it hits: set when it spawns, changed when a blast takes its legs.
var profile: ZombieProfile
## Metres per second on open ground, as the rules rolled it.
var speed: float = 1.0
var position := Vector3.ZERO
var yaw: float = 0.0
var mode: Mode = Mode.EMERGING
var mode_time: float = 0.0
## Counts every time the zombie enters a mode, so a client can restart a swing that repeats.
var episode: int = 0
var target_id: int = -1
## True once the blow of the current swing has landed (or missed).
var struck: bool = false
## Planar speed it moved at last tick.
var move_speed: float = 0.0
var lit: bool = false
## True once a blast took its legs.
var crippled: bool = false
var velocity := Vector3.ZERO
var path := PackedVector3Array()
var path_index: int = 0
var repath_left: float = 0.0
var retarget_left: float = 0.0
## Seconds until a weak-spot hit may stagger it again (a boss).
var stagger_cooldown_left: float = 0.0
## The breach it came in by and has not yet walked through (`ZombieGate.id`), or none: it stands
## outside the fence tearing boards off until the way is open.
var gate_id: StringName = &""
## Seconds of work spent on the board it is pulling at.
var tear_progress: float = 0.0


func enter(new_mode: Mode) -> void:
	mode = new_mode
	mode_time = 0.0
	struck = false
	episode = (episode + 1) & 0xFF


## The model it is drawn in.
func look() -> StringName:
	return profile.look if profile != null else ZombieModels.DEFAULT


func is_alive() -> bool:
	return mode != Mode.DYING


## What a client draws from: plain values, the same ones the wire format carries.
func view_entry() -> Dictionary:
	return {
		"id": id,
		"position": position,
		"yaw": yaw,
		"mode": mode,
		"episode": episode,
		"speed": move_speed,
		"look": look(),
	}
