extends Node
## The interact prompt card on a phone's night, with the touch layer's HUD flag off (the card as it
## was: a tap mark at its left) and on (the card without the key, #1275), over the real HUD in a
## canvas of the phone page (2337 x 1080 units for an 844 x 390 page).
## Not part of the game. Run in a window with the kit's launcher:
## `gds godot -- --path game res://tests/captures/prompt_card_touch.tscn -- --out=<folder>`
## It writes `prompt_key.png` and `prompt_no_key.png` there and quits.

const PAGE := Vector2i(2337, 1080)
const SETTLE_FRAMES := 12

var _viewport: SubViewport
var _out := "."


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	TouchMode.device_is_touch = true
	UIInputMode.track(InputEventScreenTouch.new())
	_viewport = SubViewport.new()
	_viewport.size = PAGE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var ground := ColorRect.new()
	ground.color = Color(0.18, 0.2, 0.26)
	ground.size = Vector2(PAGE)
	_viewport.add_child(ground)
	var host := Control.new()
	host.size = Vector2(PAGE)
	_viewport.add_child(host)
	var fixture := HudFixture.make(host, 1)
	var hud := fixture.hud
	fixture.into_round_one()
	hud.state.set_prompt(&"buy_door", "Projection booth door", 750)
	hud.state.set_prompt(&"buy_door", "Projection booth door with a long name that wraps", 750)
	await _settle()
	await _save("prompt_key")
	hud.touch_layout = true
	await _settle()
	await _save("prompt_no_key")
	get_tree().quit()


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	_viewport.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)
