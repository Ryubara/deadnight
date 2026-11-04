extends Node
## The special-round marquee, and the low-health frame, drawn on a real clock: how often each is
## redrawn (the engine's `draw` signal, once per `_draw`) over a few seconds, and the board's pixels
## at fixed moments, so a change to when they are redrawn can be shown to leave the look as it was
## (#934, the cause #834 found for the banner and the touch buttons).
##
## `godot --path game res://tests/captures/hud_marquee_redraw.tscn --fixed-fps 60 --
## --out=<folder> [--seconds=4] [--health=20]`. Prints the draws of each second and writes
## `marquee_<n>.png` (the board) and `full_<n>.png` (the whole HUD) at the frames in `FRAMES`.

const CANVAS := Vector2(1920, 1080)
const GROUND := Color("2a2f3a")
## The frames, from the first one after the setup, whose pictures are saved: the same moments in
## every run, because the clock is fixed.
const FRAMES: Array[int] = [20, 41, 77, 130, 181]

var _marquee_draws := 0
var _damage_draws := 0
var _viewport: SubViewport
var _fixture: HudFixture


func _ready() -> void:
	var args := _args()
	var seconds := float(str(args.get("seconds", "4")))
	var out := str(args.get("out", "user://"))
	UIMotion.reduced = false
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(CANVAS)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var ground := ColorRect.new()
	ground.color = GROUND
	ground.size = CANVAS
	_viewport.add_child(ground)
	var host := Control.new()
	host.size = CANVAS
	_viewport.add_child(host)
	_fixture = HudFixture.make(host, 1, 1958, false)
	_to_break_before(5)
	if args.has("health"):
		_fixture.hud.state.set_health(float(str(args["health"])), 100.0)
	for _i in 5:
		await get_tree().process_frame
	_fixture.hud.marquee.draw.connect(func() -> void: _marquee_draws += 1)
	_fixture.hud.damage.draw.connect(func() -> void: _damage_draws += 1)
	var frames := int(seconds * 60.0)
	var seen := 0
	for frame in frames:
		await get_tree().process_frame
		if frame in FRAMES:
			await RenderingServer.frame_post_draw
			_save(out, frame)
		if (frame + 1) % 60 == 0:
			seen += 1
			print("draws second %d: marquee %d damage %d" % [seen, _marquee_draws, _damage_draws])
			_marquee_draws = 0
			_damage_draws = 0
	print(
		"marquee visible: ",
		_fixture.hud.marquee.visible,
		" title: ",
		_fixture.hud.marquee.title_text
	)
	get_tree().quit()


func _save(out: String, frame: int) -> void:
	var image := _viewport.get_texture().get_image()
	image.save_png("%s/full_%03d.png" % [out, frame])
	var marquee := _fixture.hud.marquee
	var rect := Rect2i(marquee.get_global_rect().grow(16.0))
	image.get_region(rect).save_png("%s/marquee_%03d.png" % [out, frame])


## The night played to the break before `round_number`, every zombie killed on the way.
func _to_break_before(round_number: int) -> void:
	_fixture.act(RulesAction.start())
	while (
		_fixture.rules.round_number < round_number - 1
		or _fixture.rules.phase != GameRules.Phase.BREAK
	):
		if _fixture.rules.phase == GameRules.Phase.BREAK:
			_fixture.act(RulesAction.skip_break())
		else:
			var guard := 0
			while _fixture.rules.phase == GameRules.Phase.ACTIVE and guard < 20000:
				_fixture.act(RulesAction.tick(HudFixture.STEP * 6.0))
				for zombie_id in _fixture.rules.zombie_ids():
					_fixture.act(
						RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, HudFixture.KILLING)
					)
				guard += 1


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
