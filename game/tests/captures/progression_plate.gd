extends Control
## Capture for #1058: the menu plate (the level and its bar) of a new player with an account, then
## after a night the autopilot played with the profile file kept, read back as the menu does.
## `gds godot -- --path game res://tests/captures/progression_plate.tscn --windowed --resolution
## 1280x720 -- --out=<folder> [--rounds=4]`. Writes `before.png` and `after.png`, and prints the
## level and the XP the file holds. Uses its own profile file; the player's is never touched.

const STEP := 1.0 / 30.0
const SETTLE := 1.0
const DAY := 20401

var _out := "user://progression_plate"
var _rounds := 4


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--rounds="):
			_rounds = int(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_out)
	var path := "user://progression_plate_profile.json"
	for leftover in [path, path + ".tmp", path + ".broken"]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(leftover)
	MenuProfile.profile_path = path
	await _plate("before")
	var store := ProfileStore.open(path, func() -> bool: return true)
	await _play(store)
	await _plate("after")
	MenuProfile.profile_path = ProfileSave.DEFAULT_PATH
	get_tree().quit()


func _play(store: ProfileStore) -> void:
	var night := Night.new()
	night.challenge_board = ChallengeBoard.open(
		"user://progression_plate_board.json", ChallengeClock.fixed(DAY * 86400.0 + 60.0)
	)
	night.profile_store = store
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7)
	night.ticks_per_frame = 40
	var ticks := 0
	while night.state.rounds_started < _rounds and not night.state.over and ticks < 20000:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	night.progress.flush()
	print(
		(
			"[plate] night xp %d, credited %d, file xp %d"
			% [night.progress.xp(), night.progress.credited(), store.profile.xp]
		)
	)
	night.queue_free()
	await get_tree().process_frame


func _plate(label: String) -> void:
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.context.profile = MenuProfile.load_saved()
	shell.context.profile.display_name = "Ryubara"
	shell.context.board = FakeChallengeBoard.new()
	add_child(shell)
	UIInputMode.pointer = true
	await get_tree().process_frame
	shell.show_tab(MenuTab.Id.PLAY, false)
	for _i in int(SETTLE / STEP):
		shell.view.stage.advance(STEP)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := "%s/%s.png" % [_out, label]
	get_viewport().get_texture().get_image().save_png(file)
	var profile := shell.context.profile
	print(
		(
			"[plate] %s: level %d, xp %d, bar %.2f -> %s"
			% [label, profile.level(), profile.xp, profile.level_fraction(), file]
		)
	)
	shell.queue_free()
	await get_tree().process_frame
