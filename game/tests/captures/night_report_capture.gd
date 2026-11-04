extends Node
## The night report through the real flow (Deadnight #1068): the Play screen's night screen over a
## solo night the autopilot plays for a few rounds, then everyone goes down and the end board shows
## the report, saved as one PNG of the window. Run it through the no-focus launcher:
##
## `gds godot -- --path game res://tests/captures/night_report_capture.tscn --resolution 1280x720
## -- --out=<folder>/report.png`
##
## Arguments after `--`: `--map=ID` (default `drive_in`), `--bots=N` (default 3), `--touch` (a
## phone: use `--resolution 2340x1080`), `--rounds=N` (rounds the autopilot plays, default 3),
## `--xp=N` (the account's XP when the night begins, default 0: level 1), `--seasoned` (the opening
## night and the day's first game were paid already), `--noaccount` (no account at all: the backend
## was never reached) and `--out=FILE` (the PNG).

const NIGHT := "res://ui/screens/night_screen.tscn"
const MENU := "res://ui/screens/main_menu.tscn"
const SETTINGS_FILE := "user://night_report_capture.cfg"
const PROFILE_FILE := "user://night_report_capture_profile.json"
const SEED := 11
const GIVE_UP_SECONDS := 1200.0

var _args := {}
var _screen: NightScreen


func _ready() -> void:
	_args = _parse_args()
	_run.call_deferred()


func _run() -> void:
	Settings.path = SETTINGS_FILE
	Settings.reset_defaults()
	TouchMode.device_is_touch = _args.has("touch")
	_prepare_account()
	var settings := MatchSettings.new()
	settings.map = str(_args.get("map", "drive_in"))
	settings.bots = int(_args.get("bots", 3))
	settings.bot_skill = 2
	NightScreen.match_settings = settings.clamped()
	NightScreen.start_seed = SEED
	NightScreen.start_mode = Night.Mode.AUTOPILOT
	NightScreen.shoulder_camera = true
	NightScreen.profile_path = PROFILE_FILE
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	var night := _screen.night
	await night.ready_to_play
	night.player().local_input = false if night.player() != null else false
	await get_tree().create_timer(1.0).timeout
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	var rounds := int(_args.get("rounds", 3))
	var ticks := 0
	while night.state.rounds_started < rounds and ticks < GIVE_UP_SECONDS / Night.STEP:
		for _i in 30:
			night.tick()
			ticks += 1
		if ticks % 600 == 0:
			await get_tree().process_frame
	print("report: round ", night.state.round_number(), " after ", ticks, " ticks")
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	for _i in 4:
		night.tick()
	await get_tree().create_timer(1.5).timeout
	var board: Control = _screen.get_node("EndBoard")
	print(
		"report: board visible ", board.visible, " canvas ", get_viewport().get_visible_rect().size
	)
	var card: HudNightReport = (board as HudEndBoard).report_card
	print("report: lines ", card.lines_text, " total ", card.total_text)
	print(
		"report: ",
		card.level_text,
		" | ",
		card.progress_text,
		" | ",
		card.next_text,
		" | ",
		card.note_text
	)
	print(
		"report: card ", card.get_global_rect(), " canvas ", get_viewport().get_visible_rect().size
	)
	_save(str(_args.get("out", "user://night_report.png")))
	_clean()
	get_tree().quit()


func _prepare_account() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_FILE))
	if _args.has("noaccount"):
		TogetherApi.forget()
		return
	# A Guest account is an account (the maintainer, 2026-11-04): signed in, with XP on file.
	TogetherApi._token = "night-report-capture"
	var profile := Profile.new()
	profile.xp = int(_args.get("xp", 0))
	if _args.has("seasoned"):
		# Played before and today: no opening night, no first game of the day to pay.
		profile.opening_night = true
		profile.bonus_day = ChallengeClock.system().day()
	ProfileSave.write(profile, [], 1, PROFILE_FILE)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var target := path
	if path.begins_with("user://"):
		target = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	image.save_png(target)
	print("report: saved ", target)


func _clean() -> void:
	TogetherApi.forget()
	NightScreen.profile_path = ""
	NightScreen.start_mode = Night.Mode.HUMAN
	NightScreen.shoulder_camera = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.reset_defaults()


func _parse_args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
