extends Node
## The late-round HUD, still, for its draw cost (#948): a party of four at round 24 with the
## dead about, six perks, three weapons, the fuel gauge, the feed and the gains up, one teammate
## down, markers and a price on the prompt. A capture of the window and the draw calls of the frame
## with each part hidden in turn (`HudCostProbe`). The time-driven parts stand still, so the same
## frame comes twice and two builds can be compared pixel by pixel. Not part of the game.
##
##     godot --path game res://tests/captures/hud_cost.tscn --resolution 1920x1080
##         -- --out=<abs>/hud.png [--touch] [--nobanner] [--noportrait] [--deep]
##            [--report=<abs>/cost.json]
##
## `--touch` is the phone: the touch layout (the weapon slots under the health card) on the
## 844 x 390 window `--resolution` gives.

const NAMES := ["Ruby", "Moe", "Dee", "Cal"]
const SETTLE_FRAMES := 40
const BACKDROP := Color(0.11, 0.12, 0.16)

var _hud: Hud


func _ready() -> void:
	var args := NetArgs.new()
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(backdrop)
	layer.add_child(host)
	var fixture := HudFixture.make(host, NAMES.size(), 1958, true)
	_hud = fixture.hud
	_hud.touch_layout = args.has("touch")
	fixture.fill_late_round()
	if args.has("nobanner"):
		# A fight, not the start of a round: the banner is a few seconds a round.
		_hud.banner.showing = false
		_hud.banner.visible = false
	if args.has("noportrait"):
		# The portraits are 3D and not the same twice: leave them out to compare two builds.
		for portrait in _hud.find_children("*", "HudPortrait", true, false):
			(portrait as CanvasItem).visible = false
	for part in _hud.all_parts():
		part.set_process(false)
	_hud.set_process(false)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var probe := HudCostProbe.new()
	add_child(probe)
	var report := await probe.report(_hud, args.has("deep"))
	print("HUDCOST ", JSON.stringify(report))
	if args.has("report"):
		var file := FileAccess.open(args.get_string("report"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	if args.has("out"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.get_string("out"))
		print("SAVED ", args.get_string("out"))
	get_tree().quit()
