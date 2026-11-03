extends Node
## One window held from inside, from the player's own shoulder camera (#824): the real night on a
## map with every link sold, the dead rising only at that window's spawn, the player standing
## 2.5 m behind it facing it. A PNG when the first dead tears at the boards, at each board torn,
## and when one is in. Proves the window's dead come to it (and not to the next window along) with
## a person behind it. Not part of the game; run it windowed through the kit's private desktop:
##
##   gds godot -- --path game res://tests/captures/window_hold.tscn -- \
##       --map=small --window=upper_b1 --out=<abs folder>
##
## `--map` is `lot` or `small`; `--behind=<metres>` moves the player (default 2.5). Prints one
## line a stage and `RESULT ok` or `RESULT failed <why>`.

const LOT_SCENE := "res://world/drive_in_greybox.tscn"
const SMALL_SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const SEED := 5
const SETTLE := 30
## Physics ticks the dead get to come in before the run gives up (60 s).
const GIVE_UP := 3600

var _night: Night
var _out := ""
var _map := "small"
var _window := &"upper_b1"
var _behind := 2.5
var _boards_seen := -1


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--map="):
			_map = argument.trim_prefix("--map=")
		elif argument.begins_with("--window="):
			_window = StringName(argument.trim_prefix("--window="))
		elif argument.begins_with("--behind="):
			_behind = float(argument.trim_prefix("--behind="))
	DirAccess.make_dir_recursive_absolute(_out)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health = 1000000.0
	tuning.rounds.first_spawn_delay = 0.5
	_night = Night.new()
	_night.scene = load(LOT_SCENE if _map == "lot" else SMALL_SCENE) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	await _hold(SETTLE)
	_open_all()
	await _hold(SETTLE)
	var only_here: Array[Vector3] = []
	var gates := _night.world.spawn_gates()
	for point: Vector3 in gates:
		if gates[point] == _window:
			only_here.append(point)
	if only_here.is_empty():
		print("RESULT failed no spawn for ", _window)
		get_tree().quit(1)
		return
	_night.server.director.spawn_points = only_here
	_stand()
	await _hold(SETTLE)
	await _shot("0_boards_up")
	_act(RulesAction.skip_break())
	var tearing := false
	for tick in GIVE_UP:
		await get_tree().physics_frame
		if tick % 20 == 0:
			_stand()
		if not tearing and _someone_tearing():
			tearing = true
			await _hold(20)
			await _shot("1_tearing")
		var boards := _barricade().boards()
		if boards != _boards_seen:
			if _boards_seen >= 0:
				print("BOARDS ", boards, " at tick ", tick)
			_boards_seen = boards
			if boards == 2:
				await _shot("2_two_left")
		if boards == 0 and _someone_in():
			await _hold(30)
			await _shot("3_in")
			print("RESULT ok ", _window, " torn and walked in at tick ", tick)
			get_tree().quit()
			return
	print(
		"RESULT failed ", _window, " boards ", _barricade().boards(), " after ", GIVE_UP, " ticks"
	)
	get_tree().quit(1)


func _barricade() -> Barricade:
	return _night.world.barricade(_window)


## The player behind the window, the camera turned to it (put back each time: the dead push).
func _stand() -> void:
	var barricade := _barricade()
	var at := barricade.centre() + barricade.inward() * _behind
	at.y = barricade.global_position.y + 0.05
	var player := _night.player()
	player.teleport(at)
	var look := -barricade.inward()
	var yaw := atan2(-look.x, -look.z)
	player.state.facing = yaw
	player.rotation.y = yaw
	player.camera_rig.yaw = yaw
	player.camera_rig.pitch = deg_to_rad(-2.0)


func _someone_tearing() -> bool:
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		if zombie.tearing:
			return true
	return false


## A dead that came through the window and stands on the room's side of it.
func _someone_in() -> bool:
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		if zombie.gate_id == &"" and _barricade().depth_of(zombie.position) > 0.5:
			return true
	return false


func _open_all() -> void:
	var rules := _night.server.rules
	_act(RulesAction.grant_points(1, 100000))
	for _pass in 4:
		for item: ShopItem in rules.tuning.economy.items:
			if item.kind == ShopItem.Kind.DOOR and not rules.is_door_open(item.id):
				_act(RulesAction.buy(1, item.id))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("%s_%s.png" % [_window, name]))
	print("SHOT ", name, " boards ", _barricade().boards())


## A rules action from outside the server's tick, its events delivered as the link would.
func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
