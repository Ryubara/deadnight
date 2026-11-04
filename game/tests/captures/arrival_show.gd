extends Node
## The helicopter drop of the arrival as the player sees it (#1057), on either map and as the
## night's
## opening (the player is alone and the night starts) or as a late join (a game server of this
## process
## is a round in when the window's player comes in). Not part of the game. Run windowed, with Movie
## Maker, at a low resolution:
##
##     gds godot -- --path game res://tests/captures/arrival_show.tscn --fixed-fps 20
##         --write-movie <abs dir>/arrival.png --resolution 960x540 --quit-after 300
##         -- --map=drive_in --join=start
## `--map=` is `drive_in` or `small_indoor`; `--join=` is `start` or `late` (with `--watch=other`
## the window
## is the first player's screen while the second one drops: the others see nothing). It prints
## `SHOW` lines: the
## show's length, the frame the show ended on, and what the server said of the player at the start,
## the middle and the end of it. `--out=<abs dir>` also saves a PNG at the moments `--shots=` names
## (seconds into the show, comma separated).

const SECOND := 60

var _args := NetArgs.new()
var _night: Night
var _host: NightHost
var _other: Night
var _out := ""
var _shots: Array[float] = []
var _taken := 0


func _ready() -> void:
	_out = _args.get_string("out")
	for text in _args.get_string("shots").split(",", false):
		_shots.append(float(text))
	var map_id := _args.get_string("map") if _args.has("map") else MapRegistry.DEFAULT
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 30.0
	tuning.rounds.first_spawn_delay = 600.0
	if _args.get_string("join") == "late":
		await _join_late(tuning, map_id)
	else:
		await _join_start(tuning, map_id)
	await _run()
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


func _join_start(tuning: RulesTuning, map_id: String) -> void:
	_night = Night.new()
	_night.arrival = true
	_night.match_settings.map = map_id
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	_quiet_player()


## A server of this process, a first player (another client, drawn by hand) a round in, and the
## window's player joining then.
func _join_late(tuning: RulesTuning, map_id: String) -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = tuning
	var settings := MatchSettings.new()
	settings.map = map_id
	_host.match_settings = settings
	var hidden := SubViewport.new()
	hidden.own_world_3d = true
	hidden.size = Vector2i(64, 64)
	hidden.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(hidden)
	hidden.add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	# `--watch=other`: the window is the first player's screen, not the late joiner's: what the others
	# see.
	var watch_other := _args.get_string("watch") == "other"
	_other = Night.new()
	_other.map_id = map_id
	(self if watch_other else hidden).add_child(_other)
	await _other.start_remote(url, Night.Mode.MANUAL, 30.0)
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	for _i in 3 * SECOND:
		await get_tree().physics_frame
	_night = Night.new()
	_night.arrival = true
	_night.map_id = map_id
	(hidden if watch_other else self).add_child(_night)
	await _night.start_remote(url, Night.Mode.HUMAN, 30.0)
	_quiet_player()


func _quiet_player() -> void:
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false


func _run() -> void:
	var show := _night.arrival_show
	if show == null:
		print("SHOW none")
		return
	var seconds := show.plan.seconds()
	print("SHOW seconds=%.2f fresh=%s" % [seconds, show.plan.fresh])
	var frame := 0
	while not show.is_over():
		await get_tree().physics_frame
		frame += 1
		_report(show, frame)
		await _save_if_due(show)
	print("SHOW over after %d frames, shielded=%s" % [frame, _shielded()])
	for _i in 2 * SECOND:
		await get_tree().physics_frame
	print("SHOW after: shielded=%s grace=%s" % [_shielded(), _grace()])
	if _host != null:
		print(
			(
				"SHOW other client sees dropping=%s"
				% [_other.state.frame["players"].get(2, {}).get("dropping")]
			)
		)


func _report(show: ArrivalCutscene, frame: int) -> void:
	if frame == 1 or frame == roundi(show.plan.seconds() * SECOND * 0.5):
		print("SHOW t=%.2f shielded=%s dropping=%s" % [show.clock, _shielded(), _dropping()])


func _server() -> NightServer:
	return _host.server if _host != null else _night.server


func _state() -> PlayerState:
	return _server().rules.players.get(_night.state.player_id)


func _shielded() -> bool:
	return _state() != null and _state().is_shielded()


func _dropping() -> bool:
	return _state() != null and _state().is_dropping()


func _grace() -> float:
	return _state().grace_left if _state() != null else -1.0


func _save_if_due(show: ArrivalCutscene) -> void:
	if _out == "" or _taken >= _shots.size() or show.clock < _shots[_taken]:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/show_%02d.png" % [_out, _taken])
	_taken += 1
