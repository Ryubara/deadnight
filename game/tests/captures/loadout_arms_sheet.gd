extends Control
## Capture for #940: the Loadout stage's soldier from the menu's own camera, one picture per turn
## angle and weapon, laid out as a contact sheet (rows are weapons, columns are angles). The turn
## and the weapon switch go the way the screen does them (`MenuStageView.turn`, `preview_look`);
## the stage is stepped by hand at a fixed rate, so the pictures repeat. Run it through the
## no-focus launcher at the window's real pixels:
## `gds godot -- --path game res://tests/captures/loadout_arms_sheet.tscn --windowed --resolution
## 1280x720 -- --out=<folder> [--still] [--angles=0,45,...] [--weapons=pistol,rifle,...]`.

const STEP := 1.0 / 30.0
const SETTLE_STEPS := 45

var _out := "user://loadout_arms"
var _still := false
var _angles: Array[int] = [0, 45, 90, 135, 180, 225, 270, 315]
var _weapons: Array[StringName] = [
	&"pistol", &"smg", &"shotgun", &"rifle", &"dual_pistols", &"crowbar"
]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg == "--still":
			_still = true
		elif arg.begins_with("--angles="):
			_angles.clear()
			for part in arg.get_slice("=", 1).split(","):
				_angles.append(int(part))
		elif arg.begins_with("--weapons="):
			_weapons.clear()
			for part in arg.get_slice("=", 1).split(","):
				_weapons.append(StringName(part))
	DirAccess.make_dir_recursive_absolute(_out)
	var view := MenuStageView.new()
	view.forced_mode = MenuStageView.MODE_STILL if _still else MenuStageView.MODE_LIVE
	view.manual = true
	add_child(view)
	await get_tree().process_frame
	view.show_tab(MenuTab.Id.LOADOUT)
	for _i in SETTLE_STEPS:
		view.stage.advance(STEP)
		await get_tree().process_frame
	var cells: Array[Image] = []
	var turned := 0.0
	for weapon in _weapons:
		view.preview_look(CharacterLook.from_preset(1), weapon)
		for degrees in _angles:
			view.turn(deg_to_rad(degrees) - turned)
			turned = deg_to_rad(degrees)
			if not _still:
				for _i in SETTLE_STEPS:
					view.stage.advance(STEP)
					await get_tree().process_frame
			view.refresh()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			cells.append(_cell(get_viewport().get_texture().get_image(), view))
	var cell := cells[0].get_size()
	var sheet := Image.create(
		cell.x * _angles.size(), cell.y * _weapons.size(), false, Image.FORMAT_RGB8
	)
	for index in cells.size():
		sheet.blit_rect(
			cells[index],
			Rect2i(Vector2i.ZERO, cell),
			Vector2i((index % _angles.size()) * cell.x, (index / _angles.size()) * cell.y)
		)
	var name := "still" if _still else "live"
	sheet.save_png("%s/sheet_%s.png" % [_out, name])
	print("[loadout-arms] ", "%s/sheet_%s.png" % [_out, name], " ", sheet.get_size())
	get_tree().quit()


## The soldier's part of the window: the camera's projection of his feet and head.
func _cell(shot: Image, view: MenuStageView) -> Image:
	var scale := float(shot.get_height()) / view.size.y
	var camera := view.stage.camera
	var feet := camera.unproject_position(Vector3(0.0, 0.0, 0.0))
	var head := camera.unproject_position(Vector3(0.0, 1.9, 0.0))
	var viewport_scale := float(shot.get_height()) / float(view.viewport().size.y)
	var height := (feet.y - head.y) * viewport_scale * 1.15
	var width := height * 1.1
	var centre := Vector2((feet.x + head.x) * 0.5, (feet.y + head.y) * 0.5) * viewport_scale
	var rect := Rect2i(
		int(centre.x - width * 0.5), int(centre.y - height * 0.5), int(width), int(height)
	)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	var cut := shot.get_region(rect)
	cut.convert(Image.FORMAT_RGB8)
	cut.resize(240, 260, Image.INTERPOLATE_BILINEAR)
	return cut
