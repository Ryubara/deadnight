extends Node
## Scripted capture of the second map's sound for `docs/research/maps/small-map-audio.md` (issue
## #657): the player's camera walks the map and every sound comes from `SmallMapSounds` (and a
## teammate's `FootstepSounds`) hearing what the server would send; nothing here plays a sound
## itself. Run with Movie Maker (`--write-movie out.png --fixed-fps 10`), which writes the mix to
## `out.wav` beside the frames. Every stage prints `STAGE <seconds into the movie> <name>` and
## every sound `SOUND <seconds> <id>`, which `tools/audio/smallmap_levels.py` and
## `tools/audio/analyze.py capture --expect` read the mix against.
##
## The walk: the hall (the room tone, the yard through the boarded windows), a window's boards torn
## off and put back, the plank door opened, the rewind room, the debris taken off its stair, up the
## stair (a teammate's steps on wood), upstairs under the roof, a look out of a north window, and
## the night's end.

const MOVIE_FPS := 10.0
const EYE := 1.6
## Stage name, seconds it lasts. The camera and the events follow `_script()`.
const END_HOLD := 3.0
const TEAMMATE_ID := 2
const CAMERA_FOV := 70.0

var _camera: Camera3D
var _greybox: Node3D
var _backdrop: Node3D
var _state := ClientState.new()
var _sounds: SmallMapSounds
var _feet: FootstepSounds
var _label: Label
var _clock := 0.0
var _tick := 0
var _stages: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _total := 0.0
var _last_pos := Vector3.ZERO
var _heard := ""


func _ready() -> void:
	Audio.seed_random(657)
	Audio.played.connect(_on_played)
	_build_overlay()
	_greybox = (load("res://world/smallmap/smallmap_greybox.tscn") as PackedScene).instantiate()
	add_child(_greybox)
	_backdrop = (load("res://world/smallmap/backdrop.tscn") as PackedScene).instantiate()
	add_child(_backdrop)
	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	add_child(_camera)
	_camera.make_current()
	Audio.listener = _camera
	for _i in 6:
		await get_tree().physics_frame
	_state.player_id = 1
	_sounds = SmallMapSounds.new()
	add_child(_sounds)
	_sounds.setup(_state, _greybox, _backdrop)
	_feet = FootstepSounds.new()
	add_child(_feet)
	_feet.setup(_state, Callable(), 657)
	_script()
	_place(0.0)


func _process(delta: float) -> void:
	if _marks.is_empty() or _sounds == null:
		return
	# The sounds step on the movie's own clock (`delta` is 0.1 s under `--fixed-fps 10`).
	_clock += delta
	_place(_clock)
	_fire_events()
	_walk_teammate()
	_label.text = (
		"%s\nroom: %s  tone %.0f dB  roof %.0f dB\nlast: %s"
		% [
			_stage_at(_clock),
			_sounds.room,
			Audio.bed_fade_db(SmallMapSounds.ROOM_TONE),
			Audio.bed_fade_db(SmallMapSounds.ROOF_WIND),
			_heard,
		]
	)
	if _clock >= _total + END_HOLD:
		set_process(false)
		_finish()


func _finish() -> void:
	print("voices started: ", Audio.started, "  culled: ", Audio.culled)
	# Loops still playing when the engine shuts down are reported as leaked resources: stop them and
	# let the mixer notice before quitting.
	_sounds.queue_free()
	Audio.stop_all()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


## The camera's keyframes (where it stands and looks and when), the stages and the events.
func _script() -> void:
	var s := 0.0
	# The hall: standing in the middle, looking south at the boarded windows.
	s = _stage("hall: room tone and the yard through boarded windows", s, 7.0)
	_key(0.0, Vector3(8.0, EYE, 6.0), Vector3(8.0, 0.9, 14.0))
	_key(7.0, Vector3(8.0, EYE, 6.0), Vector3(8.0, 0.9, 14.0))
	# The first window: in line with it, the yard comes in at the window.
	s = _stage("at a window", s, 5.0)
	_key(9.0, Vector3(4.0, EYE, 9.5), Vector3(4.0, 1.4, 16.0))
	_key(12.0, Vector3(4.0, EYE, 9.5), Vector3(4.0, 1.4, 16.0))
	# The dead tear the boards off, one at a time, the last one with its own sound, then the window
	# is open.
	s = _stage("the boards come off", s, 5.0)
	_event(13.0, {"type": &"board_torn", "barricade_id": &"start_1", "boards": 3, "zombie_id": 1})
	_event(14.2, {"type": &"board_torn", "barricade_id": &"start_1", "boards": 1, "zombie_id": 1})
	_event(15.4, {"type": &"board_torn", "barricade_id": &"start_1", "boards": 0, "zombie_id": 1})
	_key(17.0, Vector3(4.0, EYE, 9.5), Vector3(4.0, 1.4, 16.0))
	s = _stage("the window is open", s, 4.0)
	_event(
		19.0, {"type": &"board_repaired", "barricade_id": &"start_1", "boards": 1, "player_id": 1}
	)
	_event(
		20.0, {"type": &"board_repaired", "barricade_id": &"start_1", "boards": 2, "player_id": 1}
	)
	_key(21.5, Vector3(4.0, EYE, 9.5), Vector3(4.0, 1.4, 16.0))
	# To the plank door at the hall's north-east corner, and through it into the rewind room.
	s = _stage("the plank door", s, 7.0)
	_key(24.5, Vector3(13.0, EYE, 3.0), Vector3(14.0, 1.4, -0.15))
	_event(26.0, {"type": &"door_opened", "door_id": &"door_side"})
	_key(28.5, Vector3(14.0, EYE, 3.0), Vector3(14.0, 1.4, -4.0))
	s = _stage("the rewind room", s, 6.0)
	_key(31.0, Vector3(14.0, EYE, -3.0), Vector3(2.0, 1.4, -4.0))
	_key(36.0, Vector3(0.0, EYE, -4.0), Vector3(-6.0, 1.4, -6.8))
	# The debris comes off the stair, and a teammate and the camera go up it.
	s = _stage("the debris blocker comes off its stair", s, 5.0)
	_event(37.0, {"type": &"door_opened", "door_id": &"door_stairs_side"})
	_key(41.0, Vector3(-4.5, EYE, -6.8), Vector3(0.0, 3.0, -6.8))
	s = _stage("up the stair on wood", s, 5.0)
	_key(44.0, Vector3(0.6, 5.0, -6.8), Vector3(6.0, 5.0, -6.8))
	_key(46.0, Vector3(0.6, 5.0, -6.8), Vector3(6.0, 5.0, -6.8))
	s = _stage("upstairs under the roof", s, 7.0)
	_key(49.0, Vector3(2.0, 5.0, -6.0), Vector3(-6.0, 5.0, -4.0))
	_key(53.0, Vector3(-3.0, 5.0, -4.0), Vector3(-3.0, 5.0, -8.0))
	s = _stage("a window onto the yard", s, 5.0)
	_key(56.0, Vector3(-1.0, 5.0, -6.2), Vector3(-1.0, 5.0, -10.0))
	_key(61.0, Vector3(-1.0, 5.0, -6.2), Vector3(-1.0, 5.0, -10.0))
	_event(62.0, {"type": &"game_over", "round_reached": 3})
	s = _stage("the night is over", s, 3.0)
	_key(64.0, Vector3(-1.0, 5.0, -6.2), Vector3(-1.0, 5.0, -10.0))
	_total = s


func _stage(name: String, from: float, seconds: float) -> float:
	_stages.append({"name": name, "t": from})
	return from + seconds


func _stage_at(t: float) -> String:
	var found := ""
	for stage in _stages:
		if stage["t"] <= t:
			found = stage["name"]
	return found


func _key(t: float, at: Vector3, look: Vector3) -> void:
	_marks.append({"t": t, "at": at, "look": look})


func _event(t: float, event: Dictionary) -> void:
	_events.append({"t": t, "event": event, "done": false})


## The camera at `t`: eased between the two keyframes round it, still after the last.
func _place(t: float) -> void:
	var before: Dictionary = _marks[0]
	var after: Dictionary = _marks[0]
	for mark in _marks:
		if mark["t"] <= t:
			before = mark
			after = mark
		else:
			after = mark
			break
	var span := maxf(after["t"] - before["t"], 0.001)
	var k := smoothstep(0.0, 1.0, clampf((t - before["t"]) / span, 0.0, 1.0))
	var at: Vector3 = (before["at"] as Vector3).lerp(after["at"], k)
	var look: Vector3 = (before["look"] as Vector3).lerp(after["look"], k)
	if at.distance_to(look) > 0.01:
		_camera.look_at_from_position(at, look)


func _fire_events() -> void:
	for item in _events:
		if not item["done"] and item["t"] <= _clock:
			item["done"] = true
			print("STAGE ", "%.1f" % _clock, " event ", item["event"]["type"])
			_state.apply_events([item["event"]])


## A teammate walks wherever the camera does, as an online night draws one: frames with a
## position, from which `FootstepSounds` reads the strides and the floor.
func _walk_teammate() -> void:
	var feet := _camera.global_position - Vector3(0.0, EYE - 0.0, 0.0)
	var from_the_camera := _last_pos.distance_to(feet) > 0.01
	_last_pos = feet
	if not from_the_camera:
		return
	_tick += maxi(1, roundi(1.0 / MOVIE_FPS / Night.STEP))
	(
		_state
		. apply_events(
			[
				{
					"type": &"frame",
					"tick": _tick,
					"players": {TEAMMATE_ID: {"pos": feet + Vector3(0.0, 0.0, 0.0)}},
					"zombies": [],
				}
			]
		)
	)


func _on_played(id: StringName, _at: Variant) -> void:
	_heard = String(id)
	print("SOUND ", "%.2f" % _clock, " ", id)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
