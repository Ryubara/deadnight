extends Node
## Two clients of one night on a game server, side by side in one window, each seeing the other
## player standing beside their own at the same lamp post, so the two screens can be compared:
## the same player is as tall and wears the same look on both. A real WebSocket on this machine;
## the server and each client live in their own world (a SubViewport each). Not part of the game.
##
##     godot --path game res://tests/captures/online_heights.tscn --resolution 1280x720
##         -- --out=<abs>/heights.png
##
## Options after `--`: `--out=<png>` (the file to write, then quit), `--look-a=N`, `--look-b=N`
## (the presets the two players wear, 2 and 5 by default).

## Each screen is a column of the game's 1920 by 1080 canvas.
const SIZE := Vector2i(958, 1080)
const SETTLE_FRAMES := 90
## Where the players stand from the lamp post, metres: side by side, the lamp ahead.
const APART := 0.55
const BACK := 5.0

var _host: NightHost
var _clients: Array[Night] = []
var _out := ""


func _ready() -> void:
	var args := NetArgs.new()
	_out = args.get_string("out")
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 4)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(row)
	var server_world := SubViewport.new()
	server_world.own_world_3d = true
	server_world.size = Vector2i(64, 64)
	server_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(server_world)
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 5
	server_world.add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var looks := [args.get_int("look-a", 2), args.get_int("look-b", 5)]
	for i in 2:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.custom_minimum_size = Vector2(SIZE)
		var view := SubViewport.new()
		view.own_world_3d = true
		view.size = SIZE
		container.add_child(view)
		row.add_child(container)
		var night := Night.new()
		night.own_look = CharacterLook.from_preset(looks[i])
		view.add_child(night)
		await night.start_remote(
			"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.HUMAN, 30.0
		)
		_clients.append(night)
		var caption := Label.new()
		caption.text = "Player %d's screen" % (i + 1)
		caption.add_theme_font_size_override(&"font_size", 36)
		caption.position = Vector2(16 + i * (SIZE.x + 4), 8)
		layer.add_child(caption)
	await _stand_by_the_lamp()
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if _out != "":
		get_viewport().get_texture().get_image().save_png(_out)
		print("SAVED ", _out)
		get_tree().quit()


## Both players beside each other a few metres south of the first lamp, facing it.
func _stand_by_the_lamp() -> void:
	var lamp: Node3D = _host.world.greybox.get_node("Field/Lamps/Lamp1")
	var at := lamp.global_position
	for i in 2:
		var spot := Vector3(at.x + (APART if i == 1 else -APART), 0.0, at.z + BACK)
		_host.server.body_of(i + 1).teleport(spot)
	for _i in 30:
		await get_tree().physics_frame
