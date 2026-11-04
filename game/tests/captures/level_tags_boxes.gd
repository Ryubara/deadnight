extends Node
## The bottom-left player boxes with each level and icon beside the name (#1077): a HUD fed with a
## party of `--players` (up to eight, the compact size from five), levels on all but a bot, and one
## player on the ground (`--down`). One PNG into `--out=<file>`. Run it through the no-focus
## launcher, not headless:
## `gds godot -- --path game res://tests/captures/level_tags_boxes.tscn --resolution 1280x720
## -- --out=<abs>/boxes.png [--players=8] [--down=2] [--touch] [--bot]`. Not part of the game.

const NAMES: Array[String] = ["Ruby", "Moe", "Dee", "Cal", "Ned", "Ivy", "Sal", "Pat"]
const LEVELS: Array[int] = [12, 7, 55, 30, 41, 9, 23, 18]


func _ready() -> void:
	var args := NetArgs.new()
	var touch := args.has("touch")
	TouchMode.device_is_touch = touch
	var players := args.get_int("players", 4)
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	var state := hud.state
	state.local_player_id = 1
	for i in players:
		state.set_player_name(i + 1, NAMES[i])
		state.apply_event(
			{"type": &"points_changed", "player_id": i + 1, "total": 1250 * (i + 1), "delta": 0}
		)
		state.set_player_level(i + 1, LEVELS[i], LEVELS[i])
	if args.has("bot"):
		state.team[players]["bot"] = true
	var down := args.get_int("down", 0)
	if down > 0:
		state.team[down]["downed"] = true
	hud.points.refresh()
	for _i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := args.get_string("out")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()
