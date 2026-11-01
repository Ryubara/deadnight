class_name ZombieView
extends Node3D
## One zombie on a client: a model and an AnimationTree, moved and animated only from the entries
## of a snapshot (`ZombieCodec.decode`). It decides nothing; it never reads the simulation.

## How far under the ground a zombie starts, and rises from, in metres.
const EMERGE_DEPTH := 1.4

var zombie_id: int = 0
## The look it is drawn in (`ZombieModels`).
var look: StringName = ZombieModels.DEFAULT
var tree: AnimationTree
## Animation time not yet advanced: the throttle spends it.
var accumulated: float = 0.0
## The throttle's current period for this zombie (it advances every Nth frame).
var period: int = 1

var _model: Node3D
var _boss := false
## The boss's lamp (its material, a copy of its own): dark once it is dead.
var _lamp: StandardMaterial3D
var _lamp_strength := 0.0
## Seconds the boss's wind-up lasts: its attack clip is played to make its blow land then.
var _telegraph := ZombieRig.BOSS_HIT_SECONDS
var _playback: AnimationNodeStateMachinePlayback
var _mode: int = -1
var _episode: int = -1
var _speed_step: int = -1
var _emerge_left: float = 0.0
var _emerge_seconds: float = 0.7


## `phase` (0 to 1) starts the walk part-way through its cycle so a crowd does not march in step.
func setup(
	model_scene: PackedScene,
	id: int,
	phase: float,
	emerge_seconds: float,
	p_look: StringName = ZombieModels.DEFAULT,
	telegraph_seconds: float = ZombieRig.BOSS_HIT_SECONDS
) -> void:
	zombie_id = id
	_emerge_seconds = emerge_seconds
	_telegraph = telegraph_seconds
	dress(model_scene, p_look)
	accumulated = phase * 1.3333  # the walk's length
	set_process(false)


## Puts the zombie in another body (its look changed: the legs went). The pose starts over from
## what the next entry says.
func dress(model_scene: PackedScene, p_look: StringName) -> void:
	if _model != null:
		_model.free()
	look = p_look
	_lamp = null
	_boss = ZombieModels.is_boss(look)
	_model = model_scene.instantiate() as Node3D
	_model.scale = Vector3.ONE * ZombieModels.GAME_SCALE
	add_child(_model)
	_strip_for_crowd(_model)
	if _boss:
		tree = ZombieRig.attach_boss(_model)
		_light_lamp(_model)
	else:
		tree = ZombieRig.attach(_model)
	_playback = tree.get(ZombieRig.PLAYBACK_PARAMETER)
	_mode = -1
	_speed_step = -1


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
	_emerge_left = maxf(_emerge_left - delta, 0.0) if mode == ZombieBody.Mode.EMERGING else 0.0
	if not _boss:
		_model.position.y = -EMERGE_DEPTH * _emerge_left / _emerge_seconds


## The body being drawn.
func model() -> Node3D:
	return _model


## Spends the accumulated animation time.
func advance_animation() -> void:
	tree.advance(accumulated)
	accumulated = 0.0


func _enter(mode: int) -> void:
	var state := ZombieRig.STATE_CRAWL if ZombieModels.crawls(look) else ZombieRig.STATE_MOVE
	match mode:
		ZombieBody.Mode.ATTACK:
			state = ZombieRig.STATE_ATTACK
			if _boss:
				tree.set(
					ZombieRig.BOSS_ATTACK_SCALE_PARAMETER, ZombieRig.BOSS_HIT_SECONDS / _telegraph
				)
		ZombieBody.Mode.STAGGER:
			state = ZombieRig.STATE_STAGGER
		ZombieBody.Mode.DYING:
			state = ZombieRig.STATE_DIE
			_light_lamp(_model, false)
		ZombieBody.Mode.EMERGING:
			_emerge_left = _emerge_seconds
			if _boss:
				state = ZombieRig.STATE_ROAR
	_playback.start(state, true)


## Lights the boss's lamp (the model's emission map, lit at the lens) or puts it out. The model's
## material is shared by every instance of the file, so the first call gives this boss a copy.
func _light_lamp(model: Node, lit: bool = true) -> void:
	if _lamp == null:
		var near := model.find_child(ZombieModels.NEAR_MESH, true, false) as MeshInstance3D
		var far := model.find_child(ZombieModels.FAR_MESH, true, false) as MeshInstance3D
		if near == null:
			return
		_lamp = near.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		_lamp_strength = _lamp.emission_energy_multiplier
		near.material_override = _lamp
		if far != null:
			far.material_override = _lamp
	_lamp.emission_energy_multiplier = _lamp_strength if lit else 0.0


## Crowd budget (kit docs godot/crowds.md): no shadows, and one mesh drawn per zombie (the
## variants' near and far meshes by visibility range; the kit zombie's eyelid mesh, if a model
## still has one, is a second draw call and goes).
func _strip_for_crowd(model: Node) -> void:
	var eyelid := model.find_child("Eyelid", true, false)
	if eyelid != null:
		eyelid.free()
	ZombieModels.set_detail_ranges(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
