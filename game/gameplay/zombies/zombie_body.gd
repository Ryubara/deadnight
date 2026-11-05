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
## Metres between the end of the last path it asked for and its target (the map's way stops short of
## a target it has no way to), and the seconds it has been chasing with a way that stops short and
## far from the target (`ZombieSim.STRAND_SECONDS`).
var path_gap: float = 0.0
var stranded_for: float = 0.0
## Seconds it has been pulling at the boards of one breach without getting through (a player puts
## them back as fast as it tears them): `ZombieSim.SIEGE_SECONDS`.
var siege_seconds: float = 0.0
var retarget_left: float = 0.0
## Seconds a blast holds it in its stagger (longer than the profile's own), while STAGGER lasts.
var stun_seconds: float = 0.0
## The ground speed a blast threw it at, along the ground; it slows to nothing (`ZombieSim`).
var push := Vector3.ZERO
## Seconds until a weak-spot hit may stagger it again (a boss).
var stagger_cooldown_left: float = 0.0
## The breach it came in by and has not yet walked through (`ZombieGate.id`), or none: it stands
## outside the fence tearing boards off until the way is open.
var gate_id: StringName = &""
## The lure it is walking to (`ZombieLure.id`), or 0 for none: a change makes it find a new way.
var lure_id: int = 0
## Seconds of work spent on the board it is pulling at.
var tear_progress: float = 0.0
## True while it stands at its boards working one loose this tick (a client plays the tear clip).
var tearing: bool = false
## How far the sill of a window lifts it above the floor it walks on now (`ZombieGate.lift_at`).
var lift: float = 0.0
## True while it climbs over a window's sill (`ZombieGate`): a client draws it scrambling.
var climbing: bool = false
## The status effect it is drawn under, as the wire id of a `StatusDef` (0 for none); the snapshot
## carries it. `ZombieSim.set_status` sets it with what the status does.
var status: int = 0
## It stands still and does not attack (a status that halts it: frozen).
var halted: bool = false
## The share of its walking speed it keeps (a status that slows it: chilled).
var slow: float = 1.0


func enter(new_mode: Mode) -> void:
	mode = new_mode
	mode_time = 0.0
	stun_seconds = 0.0
	struck = false
	episode = (episode + 1) & 0xFF


## The model it is drawn in.
func look() -> StringName:
	return profile.look if profile != null else ZombieModels.DEFAULT


func is_alive() -> bool:
	return mode != Mode.DYING


## The zombie as the weapons shoot at it (`Hitbox.ray_at`): where it stands, the size and set of
## its hit zones.
func hit_target() -> Dictionary:
	return {
		"id": id,
		"pos": position,
		"yaw": yaw,
		"scale": profile.hit_scale(),
		"weak": profile.weak,
		"pose": ZombiePose.hit_set(look(), mode, tearing, move_speed, climbing),
	}


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
		"tearing": tearing,
		"climbing": climbing and is_alive(),
		"status": status,
	}
