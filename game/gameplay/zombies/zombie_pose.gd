class_name ZombiePose
extends RefCounted
## Which hit set a zombie is shot at: its look's body (each of the looks has its own: a usher's cap
## and a farmhand's hat are on their heads) and the pose its mode puts that body in,
## the same clips the view plays (`ZombieView._enter`). The sets are fitted to the skinned meshes
## in those clips (`HitPoseData`, `tools/hit_fit/fit_hit_shapes.gd`), so a shot that touches what
## the player sees counts. Plain functions of what the server knows: no node, no animation.

const MOVE := &"move"
const STRIKE := &"strike"
const STAGGER := &"stagger"
const TEAR := &"tear"
const ROAR := &"roar"
const CLIMB := &"climb"
## Metres above the feet of an upright walker at which the bots and the autopilot aim, and of
## its head.
const UPRIGHT_CHEST := 1.1
const UPRIGHT_HEAD := 1.6
const RUN := &"run"
const SPRINT := &"sprint"


## Whether a zombie of `look` in `mode` with the snapshot's climbing bit is in its climb clip: going
## over, or flinching on the way (the upright `HitReact` would stand it in the wall). A swing at
## the sill is the swing's, and the headliner has no clip for it.
static func climbs(look: StringName, mode: int) -> bool:
	return (
		(mode == ZombieBody.Mode.CHASE or mode == ZombieBody.Mode.STAGGER)
		and not ZombieModels.is_boss(look)
	)


## The id of the hit set of `look` in `mode` (`ZombieBody.Mode`), `tearing` at the fence, moving at
## `speed` m/s, `climbing` over a sill: a run leans the head forward and a sprint dives it, so each
## has a set of its own, and a climb folds the body round its lifted feet.
static func hit_set(
	look: StringName,
	mode: int = ZombieBody.Mode.CHASE,
	tearing: bool = false,
	speed: float = 0.0,
	climbing: bool = false
) -> StringName:
	if climbing and climbs(look, mode):
		return StringName("%s.%s" % [body_of(look), CLIMB])
	var pose := MOVE
	if ZombieRig.sprint_weight(look, speed) >= 0.5:
		pose = SPRINT
	elif ZombieRig.run_weight(look, speed) >= 0.5:
		pose = RUN
	match mode:
		ZombieBody.Mode.ATTACK:
			pose = TEAR if tearing else STRIKE
		ZombieBody.Mode.STAGGER:
			pose = STAGGER
		ZombieBody.Mode.EMERGING:
			pose = ROAR if ZombieModels.is_boss(look) else MOVE
	return StringName("%s.%s" % [body_of(look), pose])


## The body a look is drawn on: its own, or the walker's for a look that has no fitted sets.
static func body_of(look: StringName) -> StringName:
	return look if look in ZombieModels.VARIANTS else ZombieModels.DEFAULT


## Where on the body to aim (`Hitbox.BODY` or `Hitbox.HEAD`), relative to the feet: straight above
## them for a zombie that stands (at the look's height, `ZombieModels.aim_scale`), and for a
## crawler, whose body lies ahead of its feet, the middle of its fitted shapes of that zone, turned
## by `yaw` (the body's the lowest of its shapes). One `climbing` over a sill is folded round its
## lifted feet: the middle of that set's shapes. A bot points at the body the player sees.
static func aim_offset(
	look: StringName, mode: int, yaw: float, zone: StringName = Hitbox.BODY, climbing: bool = false
) -> Vector3:
	var scale := ZombieModels.aim_scale(look)
	var folded := climbing and climbs(look, mode)
	if not ZombieModels.crawls(look) and not folded:
		return Vector3.UP * (UPRIGHT_HEAD if zone == Hitbox.HEAD else UPRIGHT_CHEST) * scale
	var sum := Vector3.ZERO
	var count := 0
	var lowest := Vector3.INF
	for shape: Dictionary in Hitbox.fitted(hit_set(look, mode, false, 0.0, climbing))["shapes"]:
		if shape["zone"] != zone:
			continue
		var middle := ((shape["a"] as Vector3) + (shape["b"] as Vector3)) * 0.5
		sum += middle
		count += 1
		if lowest == Vector3.INF or middle.y < lowest.y:
			lowest = middle
	if count == 0:
		return Vector3.UP * UPRIGHT_CHEST * scale
	var at := lowest if zone == Hitbox.BODY and not folded else sum / float(count)
	return Basis(Vector3.UP, yaw) * at
