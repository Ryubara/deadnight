extends Node
## The end board with the fullest night report card and the credits of a full night (Deadnight
## #1145), saved as one PNG of the window and the rectangles of what must stay on screen. Run it
## through the no-focus launcher:
##
## `gds godot -- --path game res://tests/captures/end_board_fullest_capture.tscn --resolution
## 1536x864 -- --out=<folder>/board.png`
##
## Arguments after `--`: `--players=N` (default 8), `--scale=X` (the UI scale setting, default 1:
## 1.25 makes a 1920x1080 window a 1536x864 canvas), `--phone` (a phone's safe insets),
## `--nocredits` and `--out=FILE`.

const PHONE_INSETS := Vector4(96.0, 0.0, 96.0, 24.0)

var _args := {}


func _ready() -> void:
	_args = _parse_args()
	_run.call_deferred()


func _run() -> void:
	var players := int(_args.get("players", NightHost.MAX_PLAYERS))
	get_window().content_scale_factor = float(_args.get("scale", 1.0))
	var state := EndBoardFixtures.state(players)
	var layer := CanvasLayer.new()
	add_child(layer)
	var board := HudEndBoard.new()
	layer.add_child(board)
	if _args.has("phone"):
		board.set_safe_insets(PHONE_INSETS)
	board.show_results(state, "BACK TO THE LOBBY IN", "Leave")
	board.set_left(15)
	board.show_report(EndBoardFixtures.fullest_report())
	if not _args.has("nocredits"):
		board.show_credits(EndBoardFixtures.fullest_credits(players))
	for _i in 6:
		await get_tree().process_frame
	print("board: canvas ", get_viewport().get_visible_rect().size)
	print(
		"board: card ", board.report_card.get_global_rect(), " rows ", board.report_card.row_height
	)
	print(
		"board: title ", board._title.get_global_rect(), " number ", board._number.get_global_rect()
	)
	print("board: leave ", board.leave_button.get_global_rect())
	print("board: players ", board._ticket.get_global_rect())
	print("board: credits ", board.credits_card.get_global_rect())
	var image := get_viewport().get_texture().get_image()
	var target := str(_args.get("out", "user://end_board.png"))
	if target.begins_with("user://"):
		target = ProjectSettings.globalize_path(target)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	image.save_png(target)
	print("board: saved ", target)
	get_tree().quit()


func _parse_args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
