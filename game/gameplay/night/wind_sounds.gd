class_name WindSounds
extends Node
## The drive-in's wind: a quiet steady base layer (a bed) and gusts that come and go at random, each
## a played sound (`wind_gust`, eight files of different length, rise and fall and colour) that the
## audio service plays at its own pitch, and now and then a detail on a strong gust (a loose sign, a
## rattling sheet, a tarp). A gust blows from one side of the listener and drifts round while it
## lasts, so it crosses the stereo field; the base layer breathes with the gusts and wanders on its
## own. Everything is a played sound or a bed's level, never an effect on a bus, so it is the same
## in the browser. The draws are `WindPlan`'s (seeded: a test or a capture replays them); the clock
## is the frames' own `delta`. The research is `docs/research/wind.md`.

const BASE := &"bed_wind"
const GUST := &"wind_gust"
## The base layer's level (dB under its own) before the night's character and the wander.
const BASE_REST_DB := -3.0
## How much the base layer swells (dB) with the gust that is blowing, at its peak.
const BASE_SWELL_DB := 2.0
## The length (seconds) a gust is taken to have when the service gave no player back to read it
## from.
const UNTRACKED_GUST_S := 7.0
## Seconds between one move of the base layer's level and the next.
const BASE_STEP_S := 0.25
## A gust and a detail are played from this far above the listener's feet.
const LIFT := Vector3(0.0, 1.2, 0.0)

var plan: WindPlan

## Every gust played since `start` (its `WindPlan` draw plus `at`, `length` and `file`), kept for
## the tests and the captures.
var played: Array[Dictionary] = []

var _clock := 0.0
var _running := false
var _next_gust_at := 0.0
var _gust := {}
var _pending := {}
var _details: Array[Dictionary] = []
var _base_at := 0.0
var _swell := 0.0


## The wind of a night drawn from `seed_value` (a negative one is a fresh, random night).
func setup(seed_value := -1) -> void:
	reseed(seed_value)


## Draws the night's wind again from `seed_value` (a negative one is a random seed) and, when it is
## running, schedules its first gust again.
func reseed(seed_value: int) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_ticks_usec() & 0x7fffffff)
	plan = WindPlan.new(seed_value)
	_pending = plan.next_gust()
	_next_gust_at = _clock + plan.first_gust_delay()
	played.clear()


## Starts the base layer and the gusts.
func start() -> void:
	if _running:
		return
	_running = true
	_clock = 0.0
	_next_gust_at = plan.first_gust_delay()
	_base_at = 0.0
	_swell = 0.0
	Audio.start_bed(BASE)
	_set_base()


## Stops the base layer (it fades out) and the gusts to come; a gust playing is let go.
func stop() -> void:
	_running = false
	_gust = {}
	_details.clear()
	Audio.stop_bed(BASE)


func is_running() -> bool:
	return _running


## True while a gust is blowing.
func is_blowing() -> bool:
	return not _gust.is_empty()


## How far into its swell the blowing gust is, 0 (none, or at its ends) to 1 (its peak).
func swell() -> float:
	return _swell


## Seconds the wind has run since `start`.
func clock() -> float:
	return _clock


func _process(delta: float) -> void:
	advance(delta)


## Moves the wind on by `delta` seconds: starts the next gust when its time has come, drifts the one
## blowing, plays the details that are due and moves the base layer.
func advance(delta: float) -> void:
	if not _running:
		return
	_clock += delta
	if _gust.is_empty() and _clock >= _next_gust_at:
		_start_gust()
	if not _gust.is_empty():
		_follow_gust()
	_play_due_details()
	if _clock >= _base_at:
		_base_at = _clock + BASE_STEP_S
		_set_base()


func _start_gust() -> void:
	var draw := _pending
	_pending = plan.next_gust()
	var at: Vector3 = Audio.listener_position() + _offset(draw["bearing"], draw["metres"])
	var player := Audio.play(GUST, at, draw["db"]) as AudioStreamPlayer3D
	var length := 0.0
	var file := ""
	if player != null and player.stream != null:
		length = player.stream.get_length() / maxf(player.pitch_scale, 0.01)
		file = player.stream.resource_path
	draw["at"] = _clock
	draw["length"] = length
	draw["file"] = file
	played.append(draw)
	if length <= 0.0:
		# The service gave no player back: it dropped the gust, or put it off a frame (a frame of a kill
		# starts only two sounds), when it plays untracked. Either way the lull counts from an average
		# gust.
		_next_gust_at = _clock + UNTRACKED_GUST_S + _pending["lull"]
		return
	_gust = {
		"player": player,
		"stream": player.stream,
		"start": _clock,
		"length": length,
		"bearing": draw["bearing"],
		"drift": draw["drift"],
		"metres": draw["metres"],
	}
	_next_gust_at = _clock + length + _pending["lull"]
	if draw["detail"] != &"":
		_details.append({"at": _clock + length * draw["detail_at"], "draw": draw})


## Keeps the blowing gust at its bearing round the listener (the player is moved with the listener,
## so a walking player is not left behind), and ends it when its file has played out.
func _follow_gust() -> void:
	var elapsed := _clock - float(_gust["start"])
	var length: float = _gust["length"]
	var player: AudioStreamPlayer3D = _gust["player"]
	if elapsed >= length or not is_instance_valid(player) or player.stream != _gust["stream"]:
		_swell = 0.0
		_gust = {}
		return
	var bearing: float = float(_gust["bearing"]) + float(_gust["drift"]) * elapsed
	player.global_position = Audio.listener_position() + _offset(bearing, _gust["metres"])
	_swell = pow(sin(clampf(elapsed / length, 0.0, 1.0) * PI), 2.0)


func _play_due_details() -> void:
	while not _details.is_empty() and _clock >= float(_details[0]["at"]):
		var draw: Dictionary = _details.pop_front()["draw"]
		var at: Vector3 = (
			Audio.listener_position() + _offset(draw["detail_bearing"], draw["detail_metres"])
		)
		Audio.play(draw["detail"], at, draw["detail_db"])


func _set_base() -> void:
	var db := BASE_REST_DB + plan.breeze_db + plan.walk_base() + BASE_SWELL_DB * _swell
	Audio.set_bed_level(BASE, minf(db, 0.0))


func _offset(bearing: float, metres: float) -> Vector3:
	return Vector3(sin(bearing), 0.0, cos(bearing)) * metres + LIFT


func _exit_tree() -> void:
	stop()
