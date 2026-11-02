class_name FootstepSounds
extends Node3D
## The sound of every player's feet in the night, from what a client knows: a body simulated in this
## process says when a foot comes down (`Player.footstep`, a step per `step_distance` of ground
## covered while on it, so none while airborne and a faster stride at a sprint); a player seen only
## in frames (the other players of an online night) has their stride read from their positions
## (`FootStride`). It holds no game state and asks the server nothing. The design is
## `docs/design/audio.md`.
##
## - **Your own** are quiet on purpose, flat and centred, from their own softer set
##   (`step_own_*`: no hiss, nothing above 3 kHz), well under the guns and the beds' swell: you hear
##   that you are moving without it ever being something to turn off.
## - **Everyone else's** are where their feet are, from the brighter set (`step_*`), so you hear a
##   teammate come up behind you.
## - **The ground** decides the file: gravel in the yard and the back lot, asphalt elsewhere
##   (`FootSurface`).
## - **The pace** decides the level (`level_db`): a sprint is louder, a crouch much quieter, from
##   the ground speed (a remote player's crouch is read from their slow pace).

## Lifts the sound off the ground a little, so a ray from the listener to it is not under the floor.
const FOOT_LIFT := Vector3(0.0, 0.1, 0.0)
const OWN_PREFIX := "step_own_"
const OTHER_PREFIX := "step_"

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test listens
## instead.
var play := Callable()
## `Callable(point: Vector3) -> StringName`, the surface under a point; the lot's floors unless a
## test says.
var surface_probe := Callable()
## How many steps each player's feet made here (tests and captures read it).
var counts: Dictionary[int, int] = {}

var _t := NightSoundTuning.current()
var _state: ClientState
var _bodies: Callable
var _rng := RandomNumberGenerator.new()
var _surfaces := FootSurface.new()
var _strides: Dictionary[int, FootStride] = {}
var _wired: Dictionary[int, Player] = {}
var _seconds_per_tick := Night.STEP


## `bodies` is `Callable(player_id) -> Player` (null for a player that is only a frame; a puppet,
## which never steps by itself, is only a frame to the feet too).
func setup(state: ClientState, bodies: Callable, seed_value := 1) -> void:
	_state = state
	_bodies = bodies
	_rng.seed = seed_value
	state.event_received.connect(_on_event)


## The level of a step at `speed` m/s, in dB from a walk at the run pace.
static func level_db(speed: float, sprinting: bool, crouching: bool) -> float:
	var t := NightSoundTuning.current()
	var db := t.step_db_per_decade * log(maxf(speed, 0.1) / t.step_pace) / log(10.0)
	if sprinting:
		db = maxf(db, t.step_db_per_decade * log(t.step_sprint_pace / t.step_pace) / log(10.0))
	if crouching:
		db += t.step_crouch_db
	return clampf(db, t.step_min_db, t.step_max_db)


## The sound for `surface`: the player's own set or the others'.
static func sound_for(surface: StringName, own: bool) -> StringName:
	return StringName((OWN_PREFIX if own else OTHER_PREFIX) + String(surface))


func _on_event(event: Dictionary) -> void:
	if event["type"] != &"frame":
		return
	var players: Dictionary = event["players"]
	for id: int in players:
		var body: Player = _bodies.call(id) if _bodies.is_valid() else null
		if body != null and not body.is_puppet:
			_wire(id, body)
			continue
		var stride: FootStride = _strides.get(id)
		if stride == null:
			stride = FootStride.new(_t.remote_step_distance)
			_strides[id] = stride
		var entry: Dictionary = players[id]
		var feet := stride.advance(
			event["tick"], entry["pos"], entry.get("downed", false), _seconds_per_tick
		)
		if feet > 0:
			_step(id, entry["pos"], stride.speed, false, false)
	for id: int in _strides.keys():
		if not players.has(id):
			_strides.erase(id)


func _wire(id: int, body: Player) -> void:
	if is_instance_valid(_wired.get(id)) and _wired[id] == body:
		return
	_wired[id] = body
	body.footstep.connect(_on_footstep.bind(id, body))


func _on_footstep(speed: float, sprinting: bool, id: int, body: Player) -> void:
	if not body.state.on_floor:
		return
	_step(id, body.global_position, speed, sprinting, body.state.crouching)


func _step(id: int, feet: Vector3, speed: float, sprinting: bool, crouching: bool) -> void:
	counts[id] = counts.get(id, 0) + 1
	var own := id == _state.player_id
	var sound := sound_for(_surface_at(feet), own)
	var extra := (
		level_db(speed, sprinting, crouching)
		+ _rng.randf_range(-_t.step_jitter_db, _t.step_jitter_db)
	)
	var at: Variant = null if own else feet + FOOT_LIFT
	if play.is_valid():
		play.call(sound, at, extra)
	else:
		Audio.play(sound, at, extra)


func _surface_at(point: Vector3) -> StringName:
	if surface_probe.is_valid():
		return surface_probe.call(point)
	if not is_inside_tree():
		return FootSurface.ASPHALT
	return _surfaces.at(get_world_3d().direct_space_state, point)
