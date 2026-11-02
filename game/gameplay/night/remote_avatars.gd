class_name RemoteAvatars
extends Node3D
## The other players of a night on a game server, drawn from its frames: one `Player` per player (a
## puppet: the player scene with no input, no collision and no camera), dressed in their look
## (`LookRegistry`, fed by the server's PLAYER_LOOK packets) and wearing the armband of their seat.
## Nothing moves them but the frames. A puppet is the same body as a player's own, with the same
## `PlayerAnimation`, so everything that is drawn on a body from the server's events (the weapon in
## the hand and every swap, the aim pose, the fire clip and its flash, the reload, the swing, the
## grenade clips, the repair) is drawn on it the same way: the night hands these bodies to the view
## as it hands it its own.
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
## How fast the speed an avatar walks at follows the speed the frames show, per second.
const SPEED_FOLLOW := 10.0
## How fast the barrel follows the look the frames name (they name it in steps), per second.
const PITCH_FOLLOW := 14.0
## The numbers of the player scene (the size of every character in the lot, which the names above
## their heads are placed by).
const PLAYER_TUNING := preload("res://gameplay/player/player_tuning_default.tres")
## The body of every player of the lot is the player scene, so a player is as tall, and faces the
## same way, on every screen as on their own.
const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")
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
var _avatars: Dictionary[int, Drawn] = {}
var _newest := -1.0
var _clock := -1.0


func _init() -> void:
	# Placed on the drawn frame from a track of its own: the engine's blend on top of that would
	# draw them a tick late (the night above is interpolated, docs/research/physics-interpolation.md).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


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


## The body that draws a player (a puppet `Player`), or null.
func avatar(player_id: int) -> Player:
	var drawn: Drawn = _avatars.get(player_id)
	return drawn.body if drawn != null else null


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
				"downed": player["downed"],
				"aim": player.get("aim", false),
				"pitch": player.get("pitch", 0)
			}
		)
		while track.size() > 2 and track[1]["t"] < time - KEEP:
			track.pop_front()
	for id: int in _tracks.keys():
		if not players.has(id):
			_tracks.erase(id)
			if _avatars.has(id):
				_avatars[id].body.queue_free()
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
	var body := PLAYER_SCENE.instantiate() as Player
	body.name = "Player%d" % player_id
	body.make_puppet()
	add_child(body)
	_avatars[player_id] = Drawn.new(body)
	_dress(player_id)


func _dress(player_id: int) -> void:
	var drawn: Drawn = _avatars.get(player_id)
	if drawn == null:
		return
	# Until the server has told us how they look, they wear their seat's preset.
	if _looks.looks.has(player_id) and _looks.seats.has(player_id):
		drawn.body.dress(_looks.resolved()[player_id], _looks.seats[player_id])
	else:
		drawn.body.dress(CharacterLook.from_preset(player_id - 1), player_id - 1)


func _on_look_changed(player_id: int) -> void:
	if _avatars.has(player_id):
		_dress(player_id)


func _place(player_id: int, delta: float) -> void:
	var track: Array = _tracks[player_id]
	var drawn: Drawn = _avatars[player_id]
	var last: Dictionary = track[track.size() - 1]
	draws += 1
	var pos: Vector3 = last["pos"]
	var facing: float = last["facing"]
	var pitch := float(last["pitch"])
	if _clock < last["t"]:
		for i in range(track.size() - 1, 0, -1):
			var after: Dictionary = track[i]
			var before: Dictionary = track[i - 1]
			if before["t"] <= _clock:
				var span: float = after["t"] - before["t"]
				var amount := clampf((_clock - before["t"]) / span, 0.0, 1.0) if span > 0.0 else 1.0
				pos = (before["pos"] as Vector3).lerp(after["pos"], amount)
				facing = lerp_angle(before["facing"], after["facing"], amount)
				pitch = lerpf(before["pitch"], after["pitch"], amount)
				break
			if i == 1:
				pos = before["pos"]
				facing = before["facing"]
				pitch = before["pitch"]
	else:
		starved += 1
	drawn.show_at(pos, facing, last["downed"], last["aim"], pitch * NightServer.PITCH_STEP, delta)


## One player's drawn body: placed, turned, and given the speed, the aim and the look it is moving
## with (the `PlayerAnimation` on it does the rest: the gait, the weapon, the pose).
class Drawn:
	extends RefCounted

	var body: Player
	var _was: Vector3
	var _placed := false
	var _speed := Vector3.ZERO
	var _pitch := 0.0

	func _init(p_body: Player) -> void:
		body = p_body

	func show_at(
		pos: Vector3, facing: float, downed: bool, aim: bool, pitch: float, delta: float
	) -> void:
		if _placed and delta > 0.0:
			var flat := Vector3(pos.x - _was.x, 0.0, pos.z - _was.z) / delta
			_speed = _speed.lerp(flat, 1.0 - exp(-RemoteAvatars.SPEED_FOLLOW * delta))
			_pitch = lerpf(_pitch, pitch, 1.0 - exp(-RemoteAvatars.PITCH_FOLLOW * delta))
		else:
			_pitch = pitch
		_placed = true
		_was = pos
		body.rotation.x = RemoteAvatars.DOWNED_TILT if downed else 0.0
		body.puppet_to(pos, facing, _speed, aim and not downed, _pitch)
