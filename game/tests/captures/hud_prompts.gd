extends Node
## Still of the interaction card with one of the long prompts the game makes, on a HUD that shows
## the cards around it, at the canvas a window gives (see `hud_worst_case.gd` for how).
##
## `godot --path game res://tests/captures/hud_prompts.tscn -- --out=<png>
## [--case=locker|wall|refused|circuit|fuel|link] [--window=WxH] [--crop=x,y,w,h]`. `--case=link`
## shows a paid link's card (`--link=<shop id>`, `--map=lot|small|bare`: the map's own words, or the
## lot's defaults, which is how the second map's card read before it had words of its own).
## The canvas is the project's: 1920 x 1080 stretched to the window, so `--window=844x390` is a
## phone held sideways.

const GROUND := Color("2a2f3a")
const BASE := Vector2(1920.0, 1080.0)


func _ready() -> void:
	var args := _args()
	var window := _size(str(args.get("window", "1920x1080")))
	var fit := minf(window.x / BASE.x, window.y / BASE.y)
	var canvas := window / fit
	var viewport := SubViewport.new()
	viewport.size = Vector2i(window)
	viewport.size_2d_override = Vector2i(canvas.round())
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var ground := ColorRect.new()
	ground.color = GROUND
	ground.size = canvas
	viewport.add_child(ground)
	var host := Control.new()
	host.size = canvas
	viewport.add_child(host)
	var fixture := HudFixture.make(host, 2, 1958, true)
	fixture.into_round_one()
	var state := fixture.hud.state
	state.set_ammo(6, 20, "Revolver")
	state.set_health(80.0, 100.0)
	state.apply_event({"type": &"points_changed", "player_id": 1, "total": 1250, "delta": 0})
	_case(fixture, str(args.get("case", "locker")), args)
	for _i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if args.has("crop"):
		var c := str(args["crop"]).split(",")
		image = image.get_region(Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
	var out := str(args.get("out", "user://hud_prompts.png"))
	image.save_png(out)
	print("saved ", out, " from a canvas of ", canvas)
	get_tree().quit()


func _case(fixture: HudFixture, name: String, args: Dictionary) -> void:
	var state := fixture.hud.state
	match name:
		"link":
			var words: MapWords = null
			if str(args.get("map", "lot")) == "small":
				words = (load("res://world/smallmap/smallmap_tuning.tres") as MapTuning).words
			var binding := NightHudBinding.new(
				fixture.hud, ClientState.new(), fixture.rules.tuning, null, words
			)
			var id := StringName(str(args.get("link", "door_concession")))
			binding.show_prompt({"kind": &"door", "id": id, "price": int(args.get("price", 350))})
		"wall":
			state.set_prompt(&"buy_weapon", "Double-Barrel Coach Gun", 1200)
		"refused":
			state.set_prompt(&"buy_weapon", "Hunting rifle", 1200)
			(
				fixture
				. hud
				. state
				. apply_event(
					{
						"type": &"purchase_denied",
						"player_id": 1,
						"result": GameRules.BuyResult.LOCKED,
					}
				)
			)
		"circuit":
			state.set_prompt(&"circuit", "Screen field lights: OFF", 0, "Costs 6% fuel a minute")
		"fuel":
			state.set_prompt(&"fill_fuel", "Fuel can", 150, "Fills up: +17 units of fuel")
		_:
			state.set_prompt(&"buy_ammo", "Revolver rounds", 50, "20 ROUNDS FOR YOUR RESERVE")


func _size(text: String) -> Vector2:
	var parts := text.split("x")
	return Vector2(float(parts[0]), float(parts[1]))


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
