extends Node
## A player past the lot's north fence, then back at the start (issue #862): the night's own
## server puts the body on its start marker after the grace, and the camera goes with it. Run
## windowed through the kit's capture (`gds capture frames`, 10 frames a second) with
## `-- --map=small_indoor` for the second map. Not part of the game.

const STEP_FRAMES := 6
## Where the body is put on each map, and the way the camera looks (the yaw of the view).
const OUT := {"drive_in": Vector3(0.0, 0.0, -57.0), "small_indoor": Vector3(0.0, 0.5, 32.0)}
const LOOK_YAW := {"drive_in": PI, "small_indoor": PI}

var _night: Night
var _label: Label


func _ready() -> void:
	var map_id := NetArgs.new().get_string("map", "drive_in")
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_night = Night.new()
	_night.match_settings.map = map_id
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override("font_size", 28)
	layer.add_child(_label)
	add_child(layer)
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false
	_night.server.rules.apply(RulesAction.skip_break())
	await _wait(10)
	_say("at the start")
	await _wait(10)
	# The player is past the wall (a glitch, a desync): the body of both sides is put there.
	player.teleport(OUT[map_id])
	_night.server.body_of(_night.PLAYER_ID).teleport(OUT[map_id])
	player.camera_rig.yaw = LOOK_YAW[map_id]
	player.camera_rig.snap_to(player.global_position)
	var began := _night.server.tick_count
	await _wait(1)
	while not _night.server.world.bounds.is_out(player.global_position):
		await _wait(1)
	while _night.server.world.bounds.is_out(player.global_position):
		_say("outside the map: %.1f s" % ((_night.server.tick_count - began) / 60.0))
		await _wait(1)
	_say("back at the start after %.1f s" % ((_night.server.tick_count - began) / 60.0))
	await _wait(40)
	get_tree().quit()


func _say(text: String) -> void:
	_label.text = text


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame
