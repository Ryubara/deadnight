extends Node
## A night as a phone shows it (Deadnight #1192): the real `NightScreen`, opened through the router
## so it has the game's theme, at the window's real size and the factor a night really runs at (the
## interface size alone: no phone factor). Saves one PNG of the window and prints what was measured,
## in canvas units and in real pixels. Not part of the game. Run it through the no-focus launcher:
##
## `gds godot -- --path game res://tests/captures/night_phone_capture.tscn --resolution 1688x780
## -- --shot=end --out=<folder>/end.png`
##
## A phone's page of 844 x 390 CSS px is a 1688 x 780 window (pixel ratio 2, `--ratio`),
## and a finger meets CSS pixels: the sizes it prints are in both.
##
## Arguments after `--`: `--shot=end` (the end board with the fullest report and credits),
## `--shot=pause` (the pause card), `--shot=hud` (the HUD with an objective in the bottom left,
## `--at=0.2,0.93` is where it stands on the screen), `--shot=markers` (an objective and an ally,
## standing and down, on the middle of every card of the HUD's corners: Deadnight #1218),
## `--shot=middle` (a diamond on the round banner, a teammate on the prompt and another on a popup
## card, and tags at the top edge: Deadnight #1230),
## `--on=objective@health,ally@ammo,downed@round` puts only those, `--on=free` three on free ground,
## `--touch=0` is a desktop, `--ratio=X` the page's pixel ratio, `--scale=X` (the interface size,
## default 1) and `--out=FILE`.

const PLAY := "res://ui/screens/play_screen.tscn"
const SETTINGS_PATH := "user://night_phone_capture.cfg"

var _args := {}


func _ready() -> void:
	_args = _parse_args()
	_run.call_deferred()


func _run() -> void:
	TouchMode.device_is_touch = str(_args.get("touch", "1")) != "0"
	# By the script object, so the capture also runs on a game that has no `pixel_ratio` (a "before").
	var scale_script: Object = load("res://ui/menu/menu_scale.gd")
	scale_script.set(&"pixel_ratio", float(_args.get("ratio", 2.0)))
	Settings.path = SETTINGS_PATH
	Settings.reset_defaults()
	Settings.set_value(SettingsService.UI_SCALE, float(_args.get("scale", 1.0)))
	# The first-run hints ("DRAG TO MOVE") are over the HUD once, and cover what is measured here.
	Settings.set_value(SettingsService.TOUCH_HINTS_SEEN, 255)
	PlayerLevel.use(10)
	var chosen := MatchSettings.new()
	chosen.map = "small_indoor"
	chosen.bots = 7
	chosen.count_multiplier = 1.0
	chosen.break_seconds = 9.0
	UIRouter.reset(PLAY, UITransition.Kind.CUT)
	await UIRouter.idle
	var play := UIRouter.top() as PlayScreen
	play.panel.set_settings(chosen.clamped())
	play.start()
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	if screen.night.is_arriving():
		await screen.night.arrival_ended
	# The show's black bars (7.5% of the height at the top and the bottom, `ArrivalCutscene.BAR_SHARE`)
	# and its fade stay for 0.45 s after `arrival_ended`, stepped by the physics clock: a shot taken
	# in that time shows bands a night does not have (#1261). Wait until the show has gone.
	var show_node: Node = screen.night.arrival_show
	var guard := 0
	while is_instance_valid(show_node) and guard < 600:
		await get_tree().physics_frame
		guard += 1
	var window := get_window()
	var per_unit := MenuScale.pixels_per_unit(window.size, window.content_scale_factor)
	var ratio := float(_args.get("ratio", 2.0))
	print(
		"night: window ",
		window.size,
		" factor ",
		window.content_scale_factor,
		" canvas ",
		window.get_visible_rect().size,
		" px per unit ",
		per_unit
	)
	match str(_args.get("shot", "end")):
		"end":
			await _end(screen)
		"pause":
			await _pause(screen)
		"markers":
			await _markers(screen)
		"middle":
			await _middle(screen)
		_:
			await _hud(screen)
	# The end sequence's own cards give way to the board over about two seconds of the clock.
	await get_tree().create_timer(float(_args.get("wait", 3.0))).timeout
	_report(screen, per_unit, ratio)
	var image := get_viewport().get_texture().get_image()
	var target := str(_args.get("out", "user://night_phone.png"))
	if target.begins_with("user://"):
		target = ProjectSettings.globalize_path(target)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	image.save_png(target)
	print("night: saved ", target)
	PlayerLevel.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	get_tree().quit()


func _end(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	NightFixture.run(night, 3)
	for _i in 3:
		await get_tree().process_frame
	var board: HudEndBoard = screen.get_node("EndBoard")
	board.show_report(EndBoardFixtures.fullest_report())
	board.show_credits(EndBoardFixtures.fullest_credits(8))


func _pause(screen: NightScreen) -> void:
	screen._pause()


func _hud(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	NightFixture.run(night, 3)
	night.set_paused(true)
	# The night's own markers give way to the one placed here.
	night.markers.set_process(false)
	var hud := screen._hud
	hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	var at := str(_args.get("at", "0.2,0.93")).split(",")
	var marker := HudFixture.late_marker(
		&"door", &"objective", float(at[0]), float(at[1]), 30.0, "Concession Stand", false
	)
	hud.state.set_markers([marker] as Array[Dictionary])


## Every card of the corners with an objective, a teammate or a body on its middle, in turn, so each
## kind stands under each card: the night's own markers give way to these.
func _markers(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	NightFixture.run(night, 3)
	night.set_paused(true)
	night.markers.set_process(false)
	var hud := screen._hud
	hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	hud.state.set_ammo(30, 150, "Shotgun")
	await get_tree().process_frame
	await get_tree().process_frame
	var names: Array[String] = ["Ruby", "Moe", "Cal", "Dee", "Vera"]
	var list: Array[Dictionary] = []
	var size := hud.markers.size
	var origin := hud.markers.get_global_rect().position
	if str(_args.get("on", "")) == "free":
		# On free ground, under no card: what a desktop must draw as it always did.
		(
			hud
			. state
			. set_markers(
				(
					[
						HudFixture.late_marker(
							&"a", &"objective", 0.5, 0.3, 30.0, "Concession Stand", false
						),
						HudFixture.late_marker(&"b", &"ally", 0.62, 0.55, 12.0, "Moe", false),
						HudFixture.late_marker(&"c", &"ally", 0.4, 0.6, 12.0, "Ruby", true),
					]
					as Array[Dictionary]
				)
			)
		)
		return
	var n := 0
	# `--on=objective@health,ally@ammo,downed@round`: only these, on the cards of that name.
	var only := str(_args.get("on", "")).split(",", false)
	for card in hud.corner_cards():
		if not card.is_visible_in_tree() or card.size == Vector2.ZERO:
			continue
		var middle := (card.get_global_rect().get_center() - origin) / size
		var kind := &"objective" if n % 3 == 0 else &"ally"
		var down := n % 3 == 2
		if not only.is_empty():
			kind = &""
			for entry in only:
				var pair := entry.split("@")
				if pair[1].to_lower() == str(card.name).to_lower():
					kind = &"objective" if pair[0] == "objective" else &"ally"
					down = pair[0] == "downed"
			if kind == &"":
				continue
		var shown := "Concession Stand" if kind == &"objective" else names[n % names.size()]
		var marker := HudFixture.late_marker(
			StringName("m%d" % n), kind, middle.x, middle.y, 30.0, shown, down
		)
		if kind == &"ally":
			marker["level"] = 3 + n * 7
			marker["icon"] = marker["level"]
		list.append(marker)
		n += 1
	hud.state.set_markers(list)
	print("night: markers ", n)


## Markers over the cards of the middle of the screen and at the top edge: a diamond on the round
## banner, a teammate on the prompt of a door, another on the card of a level gained, and teammates
## with and without a level on the top edge, where a tag over them would be cut.
func _middle(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	NightFixture.run(night, 3)
	night.set_paused(true)
	night.markers.set_process(false)
	var hud := screen._hud
	hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	hud.state.set_ammo(30, 150, "Shotgun")
	hud.state.set_prompt(&"buy_door", "Projection booth", 750)
	hud.state.apply_event(
		{"type": &"level_up", "player_id": hud.state.local_player_id, "level": 15, "total": 0}
	)
	for _i in 30:
		await get_tree().process_frame
		hud.popups.advance(0.05)
	var list: Array[Dictionary] = [
		HudFixture.late_marker(&"a", &"objective", 0.5, 0.1, 30.0, "Concession Stand", false),
		HudFixture.late_marker(&"b", &"ally", 0.5, 0.93, 12.0, "Ruby", false),
		HudFixture.late_marker(&"c", &"ally", 0.5, 0.3, 12.0, "Moe", false),
		HudFixture.late_marker(&"d", &"ally", 0.9, 0.0, 12.0, "Cal", false),
		HudFixture.late_marker(&"e", &"ally", 0.8, 0.0, 12.0, "Dee", true),
	]
	list[2]["level"] = 22
	list[2]["icon"] = 22
	list[3]["level"] = 41
	list[3]["icon"] = 41
	hud.state.set_markers(list)


func _report(screen: NightScreen, per_unit: float, ratio: float) -> void:
	for node in screen.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.is_visible_in_tree():
			var rect := button.get_global_rect()
			print(
				"night: button '",
				button.get("text"),
				"' ",
				rect.size,
				" units, ",
				rect.size * per_unit / ratio,
				" CSS px"
			)
	var hud := screen._hud
	var markers := hud.markers
	if "labels" in markers:
		for id: StringName in markers.labels:
			print("night: label ", id, " ", markers.labels[id])
	var cards: Array[Control] = [hud.round_part, hud.objective, hud.points, hud.health, hud.ammo]
	for card in cards:
		if card.is_visible_in_tree() and card.size != Vector2.ZERO:
			print("night: card ", card.name, " ", card.get_global_rect())


func _parse_args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
