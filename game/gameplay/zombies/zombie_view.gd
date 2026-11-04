class_name ZombieView
extends Node3D
## One zombie on a client: a model and an AnimationTree, moved and animated only from the entries
## of a snapshot (`ZombieCodec.decode`). It decides nothing; it never reads the simulation.

## How far under the ground a zombie starts, and rises from, in metres.
const EMERGE_DEPTH := 1.4
## A client of a server is sent an entry every second physics tick (30 Hz) and a view that jumped
## to each one stood still every other tick: it walks to the entry over the ticks since the last
## one instead. Past this many ticks since the last entry (a stall, a hidden tab) or this far away
## (metres: a teleport, a new life) it is set down at once.
const GLIDE_MAX_TICKS := 6
const GLIDE_MAX_JUMP := 4.0

var zombie_id: int = 0
## The look it is drawn in (`ZombieModels`).
var look: StringName = ZombieModels.DEFAULT
var tree: AnimationTree
## Animation time not yet advanced: the throttle spends it.
var accumulated: float = 0.0
## The throttle's current period for this zombie (it advances every Nth frame).
var period: int = 1

var _model: Node3D
## Draws the outline through walls (`ZombieMarks`). A bare node under the model, made with the
## body (a body is made once, in the warm-up), so marking a zombie in the middle of a night makes
## nothing.
var _outline: Outline
var _boss := false
## The status effect it is drawn under (the wire id of a `StatusDef`, 0 for none) and whether that
## one holds it still: a frozen zombie keeps its pose, the animation is not advanced.
var _status := 0
var _held := false
## Whether the tree has been advanced since the body was set going: a zombie that is first seen
## frozen is posed once and then held.
var _posed := false
## The meshes the status shell is laid over (the model's near and far variants).
var _meshes: Array[MeshInstance3D] = []
## The boss's lamp (its material, a copy of its own): dark once it is dead.
var _lamp: StandardMaterial3D
var _lamp_strength := 0.0
## Seconds the boss's wind-up lasts: its attack clip is played to make its blow land then.
var _telegraph := ZombieRig.BOSS_HIT_SECONDS
## Seconds one board takes this zombie's type (the rules' `seconds_per_board` over its
## `barrier_speed`): the tear clip is played to pull one off in exactly that.
var _board_seconds := 1.2
var _tearing := false
var _playback: AnimationNodeStateMachinePlayback
var _mode: int = -1
var _episode: int = -1
var _speed_step: int = -1
var _emerge_left: float = 0.0
var _emerge_seconds: float = 0.7
var _placed := false
## The entry being walked to: where the view was, where it goes, the yaws, and the physics ticks
## it has taken and will take (0 when it is not walking).
var _glide_from := Vector3.ZERO
var _glide_to := Vector3.ZERO
var _glide_yaw_from := 0.0
var _glide_yaw_to := 0.0
var _glide_done := 0
var _glide_total := 0
var _last_entry_tick := -1


## `phase` (0 to 1) starts the walk part-way through its cycle so a crowd does not march in step.
## A view that was parked (`park`) and is wanted in the same look is set going again as it is, with
## its model, skeleton and tree: nothing is made.
## `model_scene` may be null for such a view: it is only read when the body is made.
func setup(
	model_scene: PackedScene,
	id: int,
	phase: float,
	emerge_seconds: float,
	p_look: StringName = ZombieModels.DEFAULT,
	telegraph_seconds: float = ZombieRig.BOSS_HIT_SECONDS,
	board_seconds: float = 1.2
) -> void:
	zombie_id = id
	_emerge_seconds = emerge_seconds
	_telegraph = telegraph_seconds
	_board_seconds = maxf(board_seconds, 0.05)
	if _model == null or p_look != look:
		dress(model_scene, p_look)
	else:
		_restart()
	accumulated = phase * 1.3333  # the walk's length
	visible = true
	set_process(false)
	set_physics_process(false)


## Takes the zombie off the lot and keeps its body for the next one of its look (`ZombieHorde` keeps
## the parked views): hidden, with nothing to draw, move or animate. The tree stays `active`: it is
## advanced by hand and only by the throttle, which a parked view is not in, and switching it off
## and on throws away its resolved tracks, which the next advance rebuilds (2 ms for twenty).
func park() -> void:
	set_status(0)
	set_outlined(false)
	visible = false
	_tearing = false
	_placed = false
	_glide_total = 0
	set_physics_process(false)


## The next life of a parked body: no mode, gait or clip yet, so the first entry starts them.
func _restart() -> void:
	_posed = false
	set_status(0)
	_mode = -1
	_episode = -1
	_speed_step = -1
	_tearing = false
	_emerge_left = 0.0
	period = 1
	if _boss:
		_light_lamp(_model)


## Puts the zombie in another body (its look changed: the legs went). The pose starts over from
## what the next entry says.
func dress(model_scene: PackedScene, p_look: StringName) -> void:
	var outlined := _outline != null and _outline.enabled
	var outline_style: OutlineStyle = _outline.style if _outline != null else null
	if _model != null:
		_model.free()
	look = p_look
	_lamp = null
	_boss = ZombieModels.is_boss(look)
	_model = model_scene.instantiate() as Node3D
	_model.scale = Vector3.ONE * ZombieModels.GAME_SCALE
	add_child(_model)
	_strip_for_crowd(_model)
	_meshes.clear()
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)
	_status = 0
	_held = false
	_posed = false
	_outline = Outline.new()
	_outline.style = outline_style
	_model.add_child(_outline)
	_outline.enabled = outlined
	if _boss:
		tree = ZombieRig.attach_boss(_model)
		_light_lamp(_model)
	else:
		tree = ZombieRig.attach(_model)
	_playback = tree.get(ZombieRig.PLAYBACK_PARAMETER)
	_mode = -1
	_speed_step = -1
	_tearing = false


## Moves and animates from one decoded entry. `delta` is the time since the last entry.
func apply(entry: Dictionary, delta: float) -> void:
	set_status(entry.get("status", 0))
	_move_to(entry["position"], entry["yaw"])
	var mode: int = entry["mode"]
	var tearing: bool = entry.get("tearing", false)
	if tearing:
		# At the boards the simulation swings again and again (new episodes); the tear clip
		# loops through them and only the rules' tears (`tore`) move it.
		if not _tearing:
			_start_tearing()
	elif _tearing or mode != _mode or entry["episode"] != _episode:
		_enter(mode)
	_tearing = tearing
	_mode = mode
	_episode = entry["episode"]
	var step := roundi(entry["speed"] * 10.0)
	if step != _speed_step:
		_speed_step = step
		_set_gait(entry["speed"])
	_emerge_left = maxf(_emerge_left - delta, 0.0) if mode == ZombieBody.Mode.EMERGING else 0.0
	if not _boss:
		_model.position.y = -EMERGE_DEPTH * _emerge_left / _emerge_seconds


## Sets the zombie down at `goal`, or when entries come every few physics ticks walks it there over
## those ticks, so a 30 Hz snapshot moves it as evenly as a 60 Hz one (one entry behind).
func _move_to(goal: Vector3, yaw: float) -> void:
	var tick := Engine.get_physics_frames()
	var gap := tick - _last_entry_tick
	_last_entry_tick = tick
	if not _placed:
		# The first entry is where it appears: drawn there, not slid in from the origin.
		_placed = true
		position = goal
		rotation.y = yaw
		_glide_total = 0
		reset_physics_interpolation()
		return
	if gap <= 1 or gap > GLIDE_MAX_TICKS or position.distance_to(goal) > GLIDE_MAX_JUMP:
		position = goal
		rotation.y = yaw
		_glide_total = 0
		set_physics_process(false)
		return
	_glide_from = position
	_glide_to = goal
	_glide_yaw_from = rotation.y
	_glide_yaw_to = yaw
	_glide_done = 0
	_glide_total = gap
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _glide_total == 0:
		set_physics_process(false)
		return
	_glide_done += 1
	var share := minf(float(_glide_done) / float(_glide_total), 1.0)
	position = _glide_from.lerp(_glide_to, share)
	rotation.y = lerp_angle(_glide_yaw_from, _glide_yaw_to, share)
	if _glide_done >= _glide_total:
		_glide_total = 0
		set_physics_process(false)


## The gait for the speed it moves at: which clips are blended and how fast they are played, so
## the feet keep up with the ground (`ZombieRig.gait_rate`).
func _set_gait(speed: float) -> void:
	tree.set(ZombieRig.BLEND_PARAMETER, ZombieRig.blend_position(look, speed))
	var rate_parameter := (
		ZombieRig.CRAWL_RATE_PARAMETER
		if ZombieModels.crawls(look)
		else ZombieRig.MOVE_RATE_PARAMETER
	)
	tree.set(rate_parameter, ZombieRig.gait_rate(look, speed))


## A board this zombie was pulling at came off (the rules' `board_torn`): the clip jumps to its
## yank if it is not there already, and from here takes one board's time from yank to yank.
func tore() -> void:
	if not _tearing:
		return
	tree.set(ZombieRig.TEAR_SEEK_PARAMETER, ZombieRig.TEAR_YANK_SECONDS)
	tree.set(ZombieRig.TEAR_SCALE_PARAMETER, ZombieRig.TEAR_SECONDS / _board_seconds)
	_take_seek()


func is_tearing() -> bool:
	return _tearing


## The tear clip's playhead, in the clip's own seconds.
func tear_position() -> float:
	return _playback.get_current_play_position() if _tearing else 0.0


## The body being drawn.
func model() -> Node3D:
	return _model


## Draws the zombie's silhouette through walls in `style`, or stops (`Outline`).
func set_outlined(on: bool, style: OutlineStyle = null) -> void:
	if style != null:
		_outline.style = style
	_outline.enabled = on


func is_outlined() -> bool:
	return _outline.enabled


## The style the outline is drawn in.
func outline_style() -> OutlineStyle:
	return _outline.style


## Draws the zombie under the status effect with this wire id (`StatusDef.wire`, 0 for none): the
## status's shell over the body, and a status that holds it keeps the pose as it is.
func set_status(wire: int) -> void:
	if wire == _status:
		return
	_status = wire
	var def := StatusCatalog.by_wire(wire)
	_held = def != null and def.halts
	var shell := StatusLook.shell_for(wire)
	for mesh in _meshes:
		mesh.material_overlay = shell


## The status effect it is drawn under (a `StatusDef` wire id), 0 for none.
func status() -> int:
	return _status


## Whether a status holds it still: frozen.
func is_held() -> bool:
	return _held


## Whether the zombie is dead and falling (its entry's mode said so).
func is_dying() -> bool:
	return _mode == ZombieBody.Mode.DYING


## Spends the accumulated animation time.
func advance_animation() -> void:
	if _held and _posed:
		accumulated = 0.0
		return
	_posed = true
	tree.advance(accumulated)
	accumulated = 0.0


## It reached its boards: the first pull starts from the reach and is played so that its yank
## lands one board's time later, when the rules tear the board (its work starts from nothing).
func _start_tearing() -> void:
	_playback.start(ZombieRig.STATE_TEAR, true)
	tree.set(ZombieRig.TEAR_SEEK_PARAMETER, 0.0)
	tree.set(ZombieRig.TEAR_SCALE_PARAMETER, ZombieRig.TEAR_YANK_SECONDS / _board_seconds)
	_take_seek()


## A seek is taken on the tree's next advance, which then moves no further: taken now, so the
## time the throttle has saved up is played after it and not lost.
func _take_seek() -> void:
	tree.advance(0.0)


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
