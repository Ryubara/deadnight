extends Node
## Still of the HUD holding the longest content the game allows (`HudFixture.fill_worst_case`) on
## one canvas, to see overlaps the layout test reports. A SubViewport renders it, so the canvas can
## be smaller than the window (1536 x 864 is a 720p or 1080p window at UI scale 1.25).
##
## `godot --path game res://tests/captures/hud_worst_case.tscn -- --out=<png> [--size=1536x864]
## [--face=fallback|wide|marquee] [--busy|--night [--quiet]] [--players=N]
## [--window=WxH]`. `marquee`
## reads the files from `refs/fonts` (see `HudFonts`); `--busy` shows the layout test's own busy
## HUD, not the longest content; `--night` shows an ordinary night (the typical values). `--window`
## renders at that many pixels with the canvas stretched from `--size` the way the project's
## `canvas_items` stretch does (so `--size=1920x1080 --window=1280x720` is a 720p window).

const GROUND := Color("2a2f3a")


func _ready() -> void:
	var args := _args()
	var size_parts := str(args.get("size", "1536x864")).split("x")
	var canvas := Vector2(float(size_parts[0]), float(size_parts[1]))
	HudFonts.apply(StringName(str(args.get("face", "fallback"))))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(canvas)
	if args.has("window"):
		var window_parts := str(args["window"]).split("x")
		viewport.size = Vector2i(int(window_parts[0]), int(window_parts[1]))
		viewport.size_2d_override = Vector2i(canvas)
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
	var fixture := HudFixture.make(
		host, clampi(int(str(args.get("players", "4"))), 1, 4), 1958, true
	)
	fixture.into_round_one()
	if args.has("night"):
		_night(fixture, args.has("quiet"), clampi(int(str(args.get("players", "4"))), 1, 4))
	elif args.has("busy"):
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


## An ordinary moment: a few points, a hurt player, a weapon swap, the lot's feed and a hit or two.
func _night(fixture: HudFixture, quiet: bool, players: int) -> void:
	var hud := fixture.hud
	var state := hud.state
	if quiet:
		# The night's own start lit the lamps and showed the card; let it leave, then show the rest.
		fixture.advance(
			(
				HudTuning.current().fuel_in
				+ HudTuning.current().fuel_hold
				+ HudTuning.current().fuel_out
				+ 0.5
			)
		)
		hud.banner.show_banner("ROUND 1", "THE NIGHT BEGINS", HudBanner.Rank.ROUND)
	state.set_ammo(18, 90, "Rifle")
	state.set_equipment("Revolver", 6)
	state.set_health(70.0, 100.0)
	state.set_area("The Lot", "Open the concession stand")
	for id in range(1, players + 1):
		state.apply_event(
			{"type": &"points_changed", "player_id": id, "total": 1250 * id, "delta": 0}
		)
	hud.events_feed.push("RUBY OPENED THE CONCESSION STAND")
	if players > 1:
		hud.notices.push("%s CONNECTED" % ["", "MOE", "DEE", "CAL"][players - 1])
	for amount in [100, 60]:
		hud.gains.add_gain(&"kill", amount)
	# The generator card only shows for progress: `--quiet` leaves it away, as most of a night is.
	state.apply_event({"type": &"fuel_changed", "fuel": 62.0, "delta": 0.0 if quiet else 8.0})
	fixture.advance(HudTuning.current().fuel_in + 0.5)


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
	fixture.advance(HudTuning.current().banner_in + 0.1)


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
