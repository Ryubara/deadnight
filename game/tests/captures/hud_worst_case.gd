extends Node
## Still of the HUD holding the longest content the game allows (`HudFixture.fill_worst_case`) on
## one canvas, to see overlaps the layout test reports. A SubViewport renders it, so the canvas can
## be smaller than the window (1536 x 864 is a 720p or 1080p window at UI scale 1.25).
##
## `godot --path game res://tests/captures/hud_worst_case.tscn -- --out=<png> [--size=1536x864]
## [--face=fallback|wide|marquee] [--busy]`. `marquee` reads the files from `refs/fonts` (see
## `HudFonts`); `--busy` shows the layout test's own busy HUD, not the longest content.

const GROUND := Color("2a2f3a")


func _ready() -> void:
	var args := _args()
	var size_parts := str(args.get("size", "1536x864")).split("x")
	var canvas := Vector2(float(size_parts[0]), float(size_parts[1]))
	HudFonts.apply(StringName(str(args.get("face", "fallback"))))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(canvas)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var ground := ColorRect.new()
	ground.color = GROUND
	ground.size = canvas
	viewport.add_child(ground)
	var host := Control.new()
	host.size = canvas
	viewport.add_child(host)
	var fixture := HudFixture.make(host, 4)
	fixture.into_round_one()
	if args.has("busy"):
		_busy(fixture)
	else:
		fixture.fill_worst_case()
	for _i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := str(args.get("out", "user://hud_worst_case.png"))
	viewport.get_texture().get_image().save_png(out)
	print("saved ", out, " at ", canvas)
	get_tree().quit()


func _busy(fixture: HudFixture) -> void:
	var hud := fixture.hud
	var state := hud.state
	state.set_ammo(30, 150, "Shotgun")
	state.set_equipment("Flare", 2)
	state.set_area("The Concession Stand", "Light the booth to open the back lot")
	state.set_prompt(&"buy_door", "Projection booth door", 750)
	fixture.act(RulesAction.set_downed(2, true))
	fixture.act(RulesAction.set_downed(1, true))
	hud.banner.show_banner("ROUND 100 SURVIVED", "CATCH YOUR BREATH", HudBanner.Rank.ROUND)
	for text in ["RUBY OPENED THE PROJECTION BOOTH", "GENERATOR RUNNING LOW", "MOE IS DOWN"]:
		hud.events_feed.push(text)
	hud.notices.push("CAL CONNECTED")
	for amount in [100, 60, 130, 60]:
		hud.gains.add_gain(&"kill", amount)
	fixture.advance(HudBanner.IN_TIME + 0.1)


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
