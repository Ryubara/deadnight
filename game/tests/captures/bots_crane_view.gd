extends Node
## A hosted Rookie bot plays the prize crane, filmed from a free camera beside the glass (#1322):
## it walks up, pays, stands through the dig, and takes the rifle when it is held out. With
## `--shove` the bot is put 3.5 m off the glass as the dig begins (a teammate's walk through its
## stand did that in a real night) and shows that it walks back and still takes the prize; before
## the fix it stood out of reach until the prize faded. The crane's pool holds the rifle only and
## the dead are weighed at a round-3 walker's health, so the Rookie wants what it is dealt.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`, so no window takes the
## person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_crane_view.tscn --fixed-fps 10
## --write-movie out.png --quit-after 170 -- [--shove]`.
## Prints `MOVIE frame N: <what happened>` for the plays, the prize and the take.

const SEAT := 2
const HEALTH := 66.0
const PRIZE := &"weapon_rifle"
## Metres from the glass at which the bot starts, and to which a shove puts it.
const START_APART := 5.0
const SHOVE_APART := 3.5
const POINTS := 1000
const CAMERA_BACK := 4.5
const CAMERA_SIDE := 2.4
const CAMERA_HEIGHT := 2.1

var _night: Night
var _host := BotHost.new()
var _camera: Camera3D
var _standing := Vector3.ZERO
var _flat := Vector3.FORWARD
var _shoved := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	var tuning := RulesFixture.tuning()
	tuning.economy.item(&"crane_play").pool = [PRIZE]
	tuning.rounds.health_base = HEALTH
	tuning.rounds.intro_seconds = 1000.0
	tuning.crane.safe_plays = 99
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.server.apply({"type": NightServer.JOIN, "player_id": SEAT, "local": false})
	await get_tree().physics_frame
	_night.server.rules.apply(RulesAction.grant_points(SEAT, POINTS))
	RulesFixture.buy(_night.server.rules, 1, &"door_concession")
	await get_tree().create_timer(0.2).timeout
	_seat_the_bot()
	_place()
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)
	_host.hear(_night.server.rules.apply(RulesAction.skip_break()))


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var side := Vector3(_flat.z, 0.0, -_flat.x)
	_camera.global_position = (
		_standing - _flat * CAMERA_BACK + side * CAMERA_SIDE + Vector3(0.0, CAMERA_HEIGHT, 0.0)
	)
	_camera.look_at(_standing + _flat * 0.6 + Vector3(0.0, 1.0, 0.0))


func _seat_the_bot() -> void:
	var probe := WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world, _night.server.rules.tuning)
	var profile := BotProfile.rookie()
	profile.follows = false
	profile.shopping.assign([&"crane_play"])
	profile.saves_for.clear()
	var state := ClientState.new()
	state.player_id = SEAT
	_night.server.rules.players[SEAT].bot = true
	_host.add(BotClient.new(state, profile, 101, Callable(self, &"_send"), level))


func _send(action: Dictionary) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), SEAT)


## The camera, and the bot put some metres from the glass; the person's body is out of the shot.
func _place() -> void:
	var crane_at: Vector3 = _night.view.crane.crane.global_position
	for spot in _night.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == _night.server.rules.crane.spot:
			_standing = spot["position"]
	var toward := crane_at - _standing
	_flat = Vector3(toward.x, 0.0, toward.z).normalized()
	_night.server.body_of(1).teleport(Autopilot.HOME + Vector3(0.0, 0.1, 0.0))
	_night.server.body_of(SEAT).teleport(_on_the_mesh(_standing - _flat * START_APART))
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()


func _on_the_mesh(point: Vector3) -> Vector3:
	var snapped := NavigationServer3D.map_get_closest_point(_night.world.map(), point)
	return snapped + Vector3(0.0, 0.1, 0.0)


func _on_tick() -> void:
	_host.tick(Night.STEP)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])
	var type: StringName = event["type"]
	if type == &"crane_spin_started" and has_arg("shove") and not _shoved:
		_shoved = true
		var away := _on_the_mesh(_standing - _flat * SHOVE_APART + Vector3(1.5, 0.0, 0.0))
		_night.server.body_of(SEAT).teleport(away)
		print(
			(
				"MOVIE frame %d: the bot is put %.1f m off the glass"
				% [Engine.get_frames_drawn(), SHOVE_APART]
			)
		)
	if (
		type
		in [&"crane_spin_started", &"crane_prize_ready", &"crane_prize_taken", &"crane_prize_lost"]
	):
		print("MOVIE frame %d: %s" % [Engine.get_frames_drawn(), type])
		if type == &"crane_prize_taken" or type == &"crane_prize_lost":
			await get_tree().create_timer(1.5).timeout
			get_tree().quit()


static func has_arg(name: String) -> bool:
	return OS.get_cmdline_user_args().has("--" + name)
