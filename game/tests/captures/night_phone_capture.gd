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
## `--shot=pause` (the pause card), `--shot=settings` (its Settings, `--tab=N`),
## `--shot=hud` (the HUD with an objective in the bottom left,
## `--at=0.2,0.93` is where it stands on the screen), `--scale=X` (the interface size, default 1)
## and `--out=FILE`.

const PLAY := "res://ui/screens/play_screen.tscn"
const SETTINGS_PATH := "user://night_phone_capture.cfg"

var _args := {}


func _ready() -> void:
	_args = _parse_args()
	_run.call_deferred()


func _run() -> void:
	TouchMode.device_is_touch = true
	# By the script object, so the capture also runs on a game that has no `pixel_ratio` (a "before").
	var scale_script: Object = load("res://ui/menu/menu_scale.gd")
	scale_script.set(&"pixel_ratio", float(_args.get("ratio", 2.0)))
	# The window is the canvas: the page is the canvas over the ratio (844 x 390 CSS px at 1688 x 780).
	PageSize.css_override = Vector2(get_window().size) / float(_args.get("ratio", 2.0))
	Settings.path = SETTINGS_PATH
	Settings.reset_defaults()
	Settings.set_value(SettingsService.UI_SCALE, float(_args.get("scale", 1.0)))
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
		"settings":
			await _settings(screen)
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


## The Settings opened from the pause card (`--tab=N` is the tab, 0 to 4).
func _settings(screen: NightScreen) -> void:
	screen._pause()
	screen._open_settings()
	await get_tree().process_frame
	screen._settings.select_tab(int(_args.get("tab", 0)), false)
	await get_tree().process_frame


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
