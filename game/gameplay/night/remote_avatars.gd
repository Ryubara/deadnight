class_name RemoteAvatars
extends Node3D
## The other players of a night on a game server, drawn from its frames: one character per player,
## dressed in their look (`LookRegistry`, fed by the server's PLAYER_LOOK packets) and wearing the
## armband of their seat. Nothing moves them but the frames.
##
## They are drawn in the past: every frame adds a point to the player's track, and the avatar is
## where the track was `DELAY` seconds before the newest frame. That puts the avatar between two
## frames nearly always, so the 30 a second of the server move it smoothly at any frame rate.
## When the newest frame is older than the delay (a late packet) the avatar waits at the last point:
## `starved` counts those draws.

## How far behind the newest frame the avatars are drawn, seconds: three frames at 30 a second.
const DELAY := 0.1
## Seconds of track kept.
const KEEP := 1.0
## Ground speed (m/s) above which a character walks, and above which it runs.
const WALK_SPEED := 0.4
const RUN_SPEED := 3.6
const IDLE := "Idle"
const WALK := "Walk"
const RUN := "Run"
## The size of every character in the lot: the player scene stands its model turned half way round
## and scaled by this (`player.tscn` and `Player._ready`), so a drawn avatar is made the same way
## and a player is as tall, and faces the same way, on every screen as on their own.
const PLAYER_TUNING := preload("res://gameplay/player/player_tuning_default.tres")
## A player on the ground is turned over to lie there.
const DOWNED_TILT := -1.4

## Draws that found no frame at the clock's time, and all draws, for the numbers of a run.
var starved := 0
var draws := 0

var _looks: LookRegistry
var _skip := 0
## Seconds of a server step, to turn a frame's `tick` into time.
var _step := 1.0 / 60.0
var _tracks: Dictionary[int, Array] = {}
var _avatars: Dictionary[int, Avatar] = {}
var _newest := -1.0
var _clock := -1.0


## `skip_id` is the player this client plays, when it draws its own body itself (0 draws everyone).
func setup(looks: LookRegistry, skip_id: int, step_seconds: float) -> void:
	_looks = looks
	_skip = skip_id
	_step = step_seconds
	looks.changed.connect(_on_look_changed)


func ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_avatars.keys())
	return out


## The avatar of a player, or null.
func avatar(player_id: int) -> Node3D:
	return _avatars.get(player_id)


## The frame's players join the tracks; players that are gone lose theirs.
func apply_frame(frame: Dictionary) -> void:
	var time: float = frame["tick"] * _step
	_newest = maxf(_newest, time)
	var players: Dictionary = frame["players"]
	for id: int in players:
		if id == _skip:
			continue
		var player: Dictionary = players[id]
		if not _tracks.has(id):
			_tracks[id] = []
			_make(id)
		var track: Array = _tracks[id]
		track.append(
			{
				"t": time,
				"pos": player["pos"],
				"facing": player["facing"],
				"downed": player["downed"]
			}
		)
		while track.size() > 2 and track[1]["t"] < time - KEEP:
			track.pop_front()
	for id: int in _tracks.keys():
		if not players.has(id):
			_tracks.erase(id)
			if _avatars.has(id):
				_avatars[id].queue_free()
				_avatars.erase(id)


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock by `delta` seconds and puts every avatar where it belongs.
func advance(delta: float) -> void:
	if _newest < 0.0:
		return
	var target := _newest - DELAY
	if _clock < 0.0 or absf(_clock - target) > 0.3:
		_clock = target
	else:
		# Run on at the pace of the frames, leaning gently toward where they say the clock is.
		_clock += delta
		_clock = lerpf(_clock, target, 1.0 - exp(-4.0 * delta))
	for id: int in _avatars:
		_place(id, delta)


func _make(player_id: int) -> void:
	var avatar := Avatar.new()
	avatar.name = "Player%d" % player_id
	add_child(avatar)
	_avatars[player_id] = avatar
	_dress(player_id)


func _dress(player_id: int) -> void:
	var avatar: Avatar = _avatars.get(player_id)
	if avatar == null:
		return
	# Until the server has told us how they look, they wear their seat's preset.
	var model: Node3D
	if _looks.looks.has(player_id) and _looks.seats.has(player_id):
		model = _looks.assemble(player_id)
	else:
		model = CharacterAssembler.assemble(CharacterLook.from_preset(player_id - 1), player_id - 1)
	avatar.wear(model)


func _on_look_changed(player_id: int) -> void:
	if _avatars.has(player_id):
		_dress(player_id)


func _place(player_id: int, delta: float) -> void:
	var track: Array = _tracks[player_id]
	var avatar: Avatar = _avatars[player_id]
	var last: Dictionary = track[track.size() - 1]
	draws += 1
	var pos: Vector3 = last["pos"]
	var facing: float = last["facing"]
	if _clock < last["t"]:
		for i in range(track.size() - 1, 0, -1):
			var after: Dictionary = track[i]
			var before: Dictionary = track[i - 1]
			if before["t"] <= _clock:
				var span: float = after["t"] - before["t"]
				var amount := clampf((_clock - before["t"]) / span, 0.0, 1.0) if span > 0.0 else 1.0
				pos = (before["pos"] as Vector3).lerp(after["pos"], amount)
				facing = lerp_angle(before["facing"], after["facing"], amount)
				break
			if i == 1:
				pos = before["pos"]
				facing = before["facing"]
	else:
		starved += 1
	avatar.show_at(pos, facing, last["downed"], delta)


## One player's character: placed, turned, and set walking or running by how fast it is moving.
class Avatar:
	extends Node3D

	var _model: Node3D
	var _animation: AnimationPlayer
	var _was: Vector3
	var _placed := false
	var _clip := ""
	var _speed := 0.0

	## The character as it stands, for a test to read the parts and colours it wears.
	func model() -> Node3D:
		return _model

	func wear(model: Node3D) -> void:
		if _model != null:
			_model.queue_free()
		_model = model
		model.basis = (
			Basis(Vector3.UP, PI)
			* Basis.from_scale(Vector3.ONE * RemoteAvatars.PLAYER_TUNING.model_scale)
		)
		add_child(model)
		_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for clip in [RemoteAvatars.IDLE, RemoteAvatars.WALK, RemoteAvatars.RUN]:
			if _animation != null and _animation.has_animation(clip):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_clip = RemoteAvatars.IDLE

	func show_at(pos: Vector3, facing: float, downed: bool, delta: float) -> void:
		if _placed and delta > 0.0:
			var flat := Vector2(pos.x - _was.x, pos.z - _was.z)
			_speed = lerpf(_speed, flat.length() / delta, 1.0 - exp(-10.0 * delta))
		_placed = true
		_was = pos
		position = pos
		rotation.y = facing
		rotation.x = RemoteAvatars.DOWNED_TILT if downed else 0.0
		var want := RemoteAvatars.IDLE
		if not downed and _speed > RemoteAvatars.RUN_SPEED:
			want = RemoteAvatars.RUN
		elif not downed and _speed > RemoteAvatars.WALK_SPEED:
			want = RemoteAvatars.WALK
		if want != _clip and _animation != null and _animation.has_animation(want):
			_clip = want
			_animation.play(want, 0.15)
