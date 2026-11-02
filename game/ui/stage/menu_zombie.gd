class_name MenuZombie
extends Node3D
## One of the dead beyond the fence: a zombie model that walks a closed loop (`WanderPath`) in its
## Walk clip. No navigation mesh, no physics, no sim: its place is a function of the stage's clock.
## The clip is stepped by hand by `advance`, so a capture or a test sees the same walk.

## The Walk clip's ground speed at its authored rate for a walker (`ZombieRig.WALK_AT`).
const CLIP := &"Walk"

var path: WanderPath
var look := ZombieModels.DEFAULT

var _player: AnimationPlayer
var _clock := 0.0


## Builds the body for `zombie_look`, walking `loop` at `speed` metres a second, starting
## `start_seconds` into the lap.
static func make(
	zombie_look: StringName, loop: Array[Vector3], speed: float, start_seconds: float
) -> MenuZombie:
	var zombie := MenuZombie.new()
	zombie.look = zombie_look
	zombie.path = WanderPath.new(loop, speed)
	zombie._clock = start_seconds
	zombie.name = "Dead_%s" % zombie_look
	return zombie


func _ready() -> void:
	var model := ZombieModels.scene(look).instantiate() as Node3D
	model.scale = Vector3.ONE * ZombieModels.GAME_SCALE * ZombieModels.height_of(look)
	add_child(model)
	# The far mesh is for the gameplay camera's distance; the menu shows the near body.
	var far := model.find_child(ZombieModels.FAR_MESH, true, false) as Node3D
	if far != null:
		far.visible = false
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player != null:
		_player.get_animation(CLIP).loop_mode = Animation.LOOP_LINEAR
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_player.play(CLIP)
		_player.speed_scale = path.speed / (ZombieRig.WALK_AT * ZombieRig.clip_scale(look))
	_place()


## Moves the body `delta` seconds along its loop and steps its walk by the same.
func advance(delta: float) -> void:
	_clock += delta
	_place()
	if _player != null:
		_player.advance(delta)


func _place() -> void:
	position = path.position_at(_clock)
	var way := path.heading_at(_clock)
	rotation.y = atan2(way.x, way.z)
