class_name ZombieView
extends Node3D
## One zombie on a client: a model and an AnimationTree, moved and animated only from the entries
## of a snapshot (`ZombieCodec.decode`). It decides nothing; it never reads the simulation.

## How far under the ground a zombie starts, and rises from, in metres.
const EMERGE_DEPTH := 1.4

var zombie_id: int = 0
var tree: AnimationTree
## Animation time not yet advanced: the throttle spends it.
var accumulated: float = 0.0
## The throttle's current period for this zombie (it advances every Nth frame).
var period: int = 1

var _model: Node3D
var _playback: AnimationNodeStateMachinePlayback
var _mode: int = -1
var _episode: int = -1
var _speed_step: int = -1
var _emerge_left: float = 0.0
var _emerge_seconds: float = 0.7


## `phase` (0 to 1) starts the walk part-way through its cycle so a crowd does not march in step.
func setup(model_scene: PackedScene, id: int, phase: float, emerge_seconds: float) -> void:
	zombie_id = id
	_emerge_seconds = emerge_seconds
	_model = model_scene.instantiate() as Node3D
	add_child(_model)
	_strip_for_crowd(_model)
	tree = ZombieRig.attach(_model)
	_playback = tree.get(ZombieRig.PLAYBACK_PARAMETER)
	accumulated = phase * 1.3333  # the walk's length
	set_process(false)


## Moves and animates from one decoded entry. `delta` is the time since the last entry.
func apply(entry: Dictionary, delta: float) -> void:
	position = entry["position"]
	rotation.y = entry["yaw"]
	var mode: int = entry["mode"]
	if mode != _mode or entry["episode"] != _episode:
		_enter(mode)
	_mode = mode
	_episode = entry["episode"]
	var step := roundi(entry["speed"] * 10.0)
	if step != _speed_step:
		_speed_step = step
		tree.set(ZombieRig.BLEND_PARAMETER, entry["speed"])
	_emerge_left = maxf(_emerge_left - delta, 0.0) if mode == ZombieState.Mode.EMERGING else 0.0
	_model.position.y = -EMERGE_DEPTH * _emerge_left / _emerge_seconds


## Spends the accumulated animation time.
func advance_animation() -> void:
	tree.advance(accumulated)
	accumulated = 0.0


func _enter(mode: int) -> void:
	var state := ZombieRig.STATE_MOVE
	match mode:
		ZombieState.Mode.ATTACK:
			state = ZombieRig.STATE_ATTACK
		ZombieState.Mode.STAGGER:
			state = ZombieRig.STATE_STAGGER
		ZombieState.Mode.DYING:
			state = ZombieRig.STATE_DIE
		ZombieState.Mode.EMERGING:
			_emerge_left = _emerge_seconds
	_playback.start(state, true)


## Crowd budget (kit docs godot/crowds.md): no shadows, and one mesh per zombie (the eyelid mesh
## is a second draw call; the kit zombie loses its eyelids until a crowd variant merges them).
func _strip_for_crowd(model: Node) -> void:
	var eyelid := model.find_child("Eyelid", true, false)
	if eyelid != null:
		eyelid.free()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
