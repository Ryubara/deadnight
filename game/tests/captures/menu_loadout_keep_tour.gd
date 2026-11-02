extends Control
## Capture for #489: the Loadout tab keeps what the player picks. Pick an outfit, change the
## showcase weapon, go to another tab and back, one PNG after each step, with the stage's own words
## (look and weapon on the soldier) printed beside it. Run it through the no-focus launcher:
## `gds godot -- --path game res://tests/captures/menu_loadout_keep_tour.tscn --windowed
## --resolution 1920x1080 -- --out=<folder> [--label=name]`

const STEP := 1.0 / 30.0
const SETTLE := 1.2
## The look the player starts with, the outfit they pick, and the look and weapon steps they take.
const START_PRESET := 1
const PICKED_PRESET := 5

var _out := "user://menu_loadout_keep"
var _label := "keep"
var _shell: MenuShell
var _shot := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--label="):
			_label = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	LookStore.save_look(CharacterLook.from_preset(START_PRESET))
	UIMotion.reduced = true
	UIInputMode.pointer = true
	_shell = MenuShell.new()
	_shell.manual_stage = true
	_shell.phone_mode = 0
	_shell.context.profile = MenuProfile.from_json(
		MenuProfile.to_json("Ryubara", MenuProfile.xp_at(14) + 212, 485, {"rifle": 900})
	)
	_shell.context.board = FakeChallengeBoard.new()
	add_child(_shell)
	await get_tree().process_frame
	_shell.tab_bar.button(MenuTab.Id.LOADOUT).pressed.emit()
	await _snap("saved_look")
	var panel := _shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	panel.wardrobe.apply_preset(PICKED_PRESET)
	await _snap("outfit_picked")
	panel.selector().step(1)
	await _snap("weapon_changed")
	_shell.tab_bar.button(MenuTab.Id.SHOP).pressed.emit()
	await _snap("other_tab")
	_shell.tab_bar.button(MenuTab.Id.LOADOUT).pressed.emit()
	await _snap("back_on_loadout")
	get_tree().quit()


func _snap(step: String) -> void:
	for _i in int(SETTLE / STEP):
		_shell.view.stage.advance(STEP)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot += 1
	var file := "%s/%s_%d_%s.png" % [_out, _label, _shot, step]
	get_viewport().get_texture().get_image().save_png(file)
	var hero := _shell.view.stage.hero
	var picked := hero.look.equals(CharacterLook.from_preset(PICKED_PRESET))
	var started := hero.look.equals(CharacterLook.from_preset(START_PRESET))
	print(
		(
			"[loadout-keep] %s soldier wears: %s, holds %s"
			% [
				step,
				"the picked outfit" if picked else ("the saved outfit" if started else "other"),
				hero.weapon_id
			]
		)
	)
