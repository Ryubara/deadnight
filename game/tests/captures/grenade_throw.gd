extends Node
## A person throws a grenade in the night (#351), from the player's own camera with the HUD: the
## throw key goes in as a real key event, is held for a cook and let go; a zombie waits where the
## grenade will go off. On `main` before #351 nothing happens (the count stays, no grenade); since
## #357 the arc shows while the key is held and the grenade leaves the hand a swing after it comes
## up. Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/grenade_throw.tscn --fixed-fps 10
## --write-movie out.png --quit-after 120`.
## Each stage prints its name and the movie frame it began on.

const SECOND := 60
## The underarm toss (a short lob that lands close), cooked a moment so the cook pose holds.
const THROW_KEY := KEY_H
const COOK_SECONDS := 1.2
const FLIGHT_LIMIT := 600
const SCAN_STEPS := 36
const SCAN_REACH := 40.0
const SCAN_HEIGHT := 1.0
## The blast goes off this far from the player (m): at real size a grenade is small from the
## shoulder camera, so the throw is lobbed at a zombie close enough to read the blast.
const CLOSE_RANGE := 6.0
## The camera's pitch is nudged by this much per metre the arc's landing is off, each tick.
const AIM_GAIN := 0.004
const AIM_LIMIT := 0.9

var _night: Night
var _heard: Array[StringName] = []
var _thrown := {}


func _ready() -> void:
	# The body is made inside `Night.start` and captures the mouse when it enters the tree; a
	# recording must never hold the cursor of the person at the machine, so it is told first.
	get_tree().node_added.connect(_keep_the_mouse_free)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	await get_tree().physics_frame
	var rig := _night.player().camera_rig
	rig.yaw = _open_yaw()
	rig.snap_to(_night.player().global_position)
	_night.state.event_received.connect(_on_event)
	var rules := _night.server.rules
	var zombie_id := await _first_zombie()
	await _wait(SECOND * 3)
	var body: ZombieBody = _night.server.sim.zombies[zombie_id]
	_stage("ready, %d grenades" % rules.grenades_of(_night.PLAYER_ID))
	_key(THROW_KEY, true)
	_stage("key down: cooking")
	await _aim_close(roundi(COOK_SECONDS * SECOND), rig)
	_key(THROW_KEY, false)
	_stage("key up: the arm swings")
	for _i in SECOND:
		if _heard.has(&"grenade_thrown"):
			break
		await get_tree().physics_frame
	_stage("the grenade leaves the hand")
	var spot := _blast_spot()
	for _i in SECOND * 4:
		if not _heard.has(&"grenade_exploded") and spot != Vector3.ZERO:
			body.position = spot
			body.velocity = Vector3.ZERO
		await get_tree().physics_frame
	_stage(
		(
			"end: %d grenades, thrown %s, exploded %s"
			% [
				rules.grenades_of(_night.PLAYER_ID),
				_heard.has(&"grenade_thrown"),
				_heard.has(&"grenade_exploded")
			]
		)
	)
	get_tree().quit()


## Holds the key for `frames` ticks and tilts the camera until the arc the preview draws comes down
## `CLOSE_RANGE` metres away (the same arc the server throws), then keeps it there.
func _aim_close(frames: int, rig: ThirdPersonCamera) -> void:
	var from := _night.player().global_position
	var apart := 0.0
	for _i in frames:
		await get_tree().physics_frame
		var landing := _night.preview.landing()
		if landing == Vector3.ZERO:
			continue
		apart = Vector2(landing.x - from.x, landing.z - from.z).length()
		rig.pitch = clampf(rig.pitch + (CLOSE_RANGE - apart) * AIM_GAIN, -AIM_LIMIT, AIM_LIMIT)
	print("aimed: pitch %.3f, lands %.1f m away" % [rig.pitch, apart])


func _keep_the_mouse_free(node: Node) -> void:
	if node is Player:
		(node as Player).capture_mouse = false


## The way the player can see furthest (a throw there flies a while before it meets a wall).
func _open_yaw() -> float:
	var cast := WorldCast.new(_night.get_world_3d().direct_space_state)
	var from := _night.player().global_position + Vector3.UP * SCAN_HEIGHT
	var best := 0.0
	var best_free := -1.0
	for i in SCAN_STEPS:
		var yaw := TAU * i / SCAN_STEPS
		var ahead := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var hit := cast.cast(from, from + ahead * SCAN_REACH)
		var free: float = hit["distance"] if not hit.is_empty() else SCAN_REACH
		if free > best_free:
			best_free = free
			best = yaw
	return best


func _on_event(event: Dictionary) -> void:
	_heard.append(event["type"])
	if event["type"] == &"grenade_thrown":
		_thrown = event


func _first_zombie() -> int:
	for _i in 900:
		await get_tree().physics_frame
		if not _night.server.sim.zombies.is_empty():
			return _night.server.sim.zombies.keys()[0]
	return -1


## Where the thrown grenade goes off, from the server's own throw event; zero before it is known.
func _blast_spot() -> Vector3:
	if _thrown.is_empty():
		return Vector3.ZERO
	var thrown := _thrown
	var cast := WorldCast.new(_night.get_world_3d().direct_space_state)
	var copy := GrenadeState.new(
		0,
		1,
		load("res://gameplay/grenades/defs/frag.tres"),
		thrown["position"],
		thrown["velocity"],
		thrown["fuse_left"]
	)
	for _i in FLIGHT_LIMIT:
		copy.step(Night.STEP, cast.callable())
		if copy.is_spent():
			break
	return copy.position + Vector3(1.0, -0.1, 0.0)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
