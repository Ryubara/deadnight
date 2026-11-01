extends Node
## The concession's breaker in a night, for captures: the stand after its door is bought (dark, as
## it was when nothing could light it), the player walking up to the post with the HUD's prompt,
## the breaker thrown and the stand lighting up, and the same on a second throw (off). On a branch
## with no breaker posts it takes only the dark views. Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/switches.tscn --fixed-fps 10 --write-movie out.png`.
## Each stage prints its name and the movie frame it began on.

const DOOR := &"door_concession"
const CIRCUIT := &"concession"
## Looking in at the stand through its front door, from the field.
const DOOR_FROM := Vector3(0.0, 1.6, -7.6)
const DOOR_AT := Vector3(0.0, 1.2, 3.0)
## The front of the stand and the post, from the north-east, a little above head height.
const WIDE_FROM := Vector3(15.0, 3.2, -11.0)
const WIDE_AT := Vector3(3.0, 1.6, -4.5)
## The player at the post, seen from behind and above.
const POST_FROM := Vector3(11.4, 2.6, -10.2)
const POST_AT := Vector3(8.5, 1.1, -5.0)
const GIVE_UP_FRAMES := 4000
const SETTLE_FRAMES := 30

var _night: Night
var _camera: Camera3D


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()
	_act(RulesAction.grant_points(1, 500))
	_act(RulesAction.buy(1, DOOR))
	await _until(func() -> bool: return not _night.world.navigation.is_busy())
	await _hold(SETTLE_FRAMES)
	_look(DOOR_FROM, DOOR_AT)
	_stage("dark_through_the_door")
	await _hold(SETTLE_FRAMES)
	_look(WIDE_FROM, WIDE_AT)
	_stage("dark_from_outside")
	await _hold(SETTLE_FRAMES)
	if not "switches" in _night.world:
		await _finish()
		return
	# Untyped, so the same script also runs on a branch that has no breaker posts.
	var post = _night.world.get("switches").post(CIRCUIT)
	_night.player().teleport(post.standing_point(1.4) + Vector3(0.0, 0.1, 0.0))
	_look(POST_FROM, POST_AT)
	await _hold(SETTLE_FRAMES)
	_stage("at_the_post")
	await _hold(SETTLE_FRAMES)
	var use := NightCommand.new()
	use.use = true
	use.motion.yaw = PI
	_night.link.send(use.to_dict())
	await _hold(2)
	_stage("thrown")
	await _hold(SETTLE_FRAMES)
	_look(WIDE_FROM, WIDE_AT)
	await _hold(SETTLE_FRAMES)
	_stage("lit_from_outside")
	await _hold(SETTLE_FRAMES)
	_look(DOOR_FROM, DOOR_AT)
	await _hold(SETTLE_FRAMES)
	_stage("lit_through_the_door")
	await _hold(SETTLE_FRAMES)
	await _finish()


func _finish() -> void:
	# A bake the door started runs on a worker thread; quitting under it kills the engine.
	await _until(func() -> bool: return not _night.world.navigation.is_busy())
	await _hold(10)
	get_tree().quit()


func _look(from: Vector3, at: Vector3) -> void:
	_camera.look_at_from_position(from, at)


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


## A rules action from outside the server's tick, its events delivered as the link would.
func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _until(done: Callable) -> void:
	for _i in GIVE_UP_FRAMES:
		if done.call():
			return
		await get_tree().physics_frame
	push_error("switches capture: gave up waiting")
	get_tree().quit()
