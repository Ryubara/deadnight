extends Node
## The right thumb's buttons on a phone's night, for captures (#1277): the controls over a plain
## ground, a canvas of the real phone page (2337 x 1080 units for an 844 x 390 page), at rest, with
## a thumb on Reload, with Crouch toggled on, and with the interact button up (its verb under the
## tap mark).
## Not part of the game. Run in a window with the kit's launcher:
## `gds godot -- --path game res://tests/captures/touch_icons_sheet.tscn -- --out=<folder>`
## It writes `rest.png`, `reload_held.png`, `crouch_on.png` and `interact.png` there and quits.

const PAGE := Vector2i(2337, 1080)
const SETTLE_FRAMES := 12

var _viewport: SubViewport
var _controls: TouchControls
var _out := "."


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	TouchMode.device_is_touch = true
	_viewport = SubViewport.new()
	_viewport.size = PAGE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var ground := ColorRect.new()
	ground.color = Color(0.18, 0.2, 0.26)
	ground.size = Vector2(PAGE)
	_viewport.add_child(ground)
	var state := HudState.new()
	_controls = TouchControls.new()
	_controls.state = state
	_controls.persist_hints = false
	_viewport.add_child(_controls)
	_controls.size = Vector2(PAGE)
	_controls.refresh()
	await _settle()
	await _save("rest")
	_controls._touch_down(0, _circle(TouchLayout.RELOAD))
	await _settle()
	await _save("reload_held")
	_controls._touch_up(0)
	_controls._touch_down(1, _circle(TouchLayout.CROUCH))
	_controls._touch_up(1)
	await _settle()
	await _save("crouch_on")
	state.set_prompt(&"buy_door", "Projection booth door", 750)
	await _settle()
	await _save("interact")
	get_tree().quit()


func _circle(id: StringName) -> Vector2:
	return _controls.button_circle(id)[&"centre"]


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	_viewport.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)
