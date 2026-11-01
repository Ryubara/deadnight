extends Node
## Hip fire from the player's shoulder camera in a real night (HUD over it): the player looks away
## from the way the body faces, then holds the trigger without aiming, then lets go. Real input
## actions on a timeline of physics seconds, so the same script films the camera before and after a
## change. Not part of the game. Run with Movie Maker (fixed time step, no real clock):
##
##     godot --path game res://tests/captures/hip_fire_tour.tscn --write-movie <abs>/hip.png \
##         --fixed-fps 10 --resolution 1280x720 --quit-after 70 [-- --aim]
##
## With `--aim` the trigger is held with the aim button too (the full aim zoom, for comparison).
## Prints STAGE <name> <frame> as each stage starts (frame = seconds x 10).

const TICKS_PER_SECOND := 60.0
const MOVIE_FPS := 10.0
## The view is turned this far to the right of the body, in degrees.
const LOOK_AWAY := 75.0
## Where the player stands in the avenue and which way the body and view face, degrees (180 is
## down the lot, toward the road).
const START := Vector3(0.0, 0.05, -28.0)
const START_YAW := 180.0
## [seconds, kind, argument]: `stage` names a stage; `look` turns the view; `press` and `release`
## hold an input action; `end` quits.
const TIMELINE := [
	[0.0, "stage", "stand"],
	[1.0, "stage", "look_away"],
	[1.0, "look", LOOK_AWAY],
	[1.8, "stage", "fire"],
	[1.8, "press", "fire"],
	[3.4, "stage", "release"],
	[3.4, "release", "fire"],
	[5.6, "stage", "settled"],
	[6.5, "end", ""],
]

var _ticks := 0
var _next := 0
var _night: Night
var _aim := false


func _ready() -> void:
	_aim = OS.get_cmdline_user_args().has("--aim")
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	var player := _night.player()
	player.capture_mouse = false
	player.teleport(START)
	player.state.facing = deg_to_rad(START_YAW)
	player.rotation.y = player.state.facing
	player.camera_rig.yaw = player.state.facing
	_ticks = 0


func _physics_process(_delta: float) -> void:
	if _night == null or not _night.running:
		return
	var now := _ticks / TICKS_PER_SECOND
	_ticks += 1
	while _next < TIMELINE.size() and TIMELINE[_next][0] <= now:
		var entry: Array = TIMELINE[_next]
		_next += 1
		_run(entry[1], entry[2])


func _run(kind: String, argument: Variant) -> void:
	match kind:
		"stage":
			print("STAGE %s %d" % [argument, roundi(_ticks / TICKS_PER_SECOND * MOVIE_FPS)])
		"look":
			_night.player().camera_rig.apply_look(deg_to_rad(float(argument)), 0.0)
		"press":
			Input.action_press(argument)
			if _aim:
				Input.action_press("aim")
		"release":
			Input.action_release(argument)
			Input.action_release("aim")
		"end":
			get_tree().quit()
