extends Node
## A heavy grenade thrown into a pack of the dead (#680), from the player's camera with the HUD: the
## dead stand in a bunch down the open way, the throw key goes in as a real key event, the grenade
## flies low, runs into the first of them, drops at its feet, beeps faster and faster and goes off
## among the pack. Not part of the game. Run with Movie Maker through the kit's launcher: `gds godot
## -- --path game res://tests/captures/grenade_pack.tscn --fixed-fps 30 --write-movie
## <folder>/pack.png --quit-after 700 [-- side]`; `side` looks from beside the throw instead of over
## the player's shoulder. The wait for the dead to arrive runs at ten times the speed. Each stage
## prints its name and the movie frame it began on; the numbers a reader checks (where it stopped
## against the zombie it hit, the beeps' times) are printed at the end.

const SECOND := 60
const THROW_KEY := KEY_G
const COOK_SECONDS := 0.4
const PACK_SIZE := 4
## The pack's first zombie stands this far from the player down the open way, the others behind it.
const PACK_FRONT := 6.5
const FLIGHT_LIMIT := 900
const WAIT_SPEED := 10.0
## The side view: how far forward and to the side of the player the camera stands (forward, up, to
## the side).
const SIDE_CAMERA := Vector3(-1.5, 3.4, 2.2)
const SIDE_TARGET_FORWARD := 5.2
const SCAN_STEPS := 36
const SCAN_REACH := 40.0
const SCAN_HEIGHT := 1.0

var _night: Night
var _heard: Array[Dictionary] = []
var _beeps: Array[float] = []
var _clock := 0.0
## Where each of the dead stands: the sim walks them, so they are put back every tick.
var _spots: Dictionary[ZombieBody, Vector3] = {}


func _ready() -> void:
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
	var yaw := _open_yaw()
	rig.yaw = yaw
	rig.snap_to(_night.player().global_position)
	_night.state.event_received.connect(_on_event)
	var grenades := _night.get_node("GrenadeSounds") as GrenadeSounds
	var played := grenades.play
	grenades.play = func(id: StringName, at: Variant, db: float) -> void:
		if id == &"grenade_beep":
			_beeps.append(_clock)
		var voice: Node = Audio.play(id, at, db)
		if id == &"grenade_beep" and _asked("debug"):
			var p3 := voice as AudioStreamPlayer3D
			print(
				(
					"BEEP at %s db %.1f occlusion %.1f vol %.1f cutoff %.0f playing %s bus %s unit %.1f maxd %.1f"
					% [
						at,
						db,
						Audio.occlusion_between(Audio.listener_position(), at),
						p3.volume_db,
						p3.attenuation_filter_cutoff_hz,
						p3.playing,
						p3.bus,
						p3.unit_size,
						p3.max_distance
					]
				)
			)
		if played.is_valid():
			played.call(id, at, db)
	Engine.time_scale = WAIT_SPEED
	await _wait_for_zombies()
	Engine.time_scale = 1.0
	var pack := _stand_the_pack(yaw)
	if _asked("side"):
		_look_from_the_side(yaw)
	for _i in SECOND:
		_hold_the_pack()
		await _tick()
	_stage("the pack stands %.1f m away, %d dead" % [PACK_FRONT, pack.size()])
	_key(THROW_KEY, true)
	await _wait(roundi(COOK_SECONDS * SECOND))
	_key(THROW_KEY, false)
	_stage("key up: the arm swings")
	var exploded := false
	for _i in FLIGHT_LIMIT:
		_hold_the_pack()
		await _tick()
		if _exploded():
			if not exploded:
				_stage("the blast")
			exploded = true
			if _clock > _blast_time() + 1.6:
				break
	_report(pack)
	_publish("done", true)
	get_tree().quit()


func _look_from_the_side(yaw: float) -> void:
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	var feet := _night.player().global_position
	var camera := Camera3D.new()
	camera.fov = 62.0
	add_child(camera)
	camera.global_position = (
		feet + forward * SIDE_CAMERA.x + Vector3.UP * SIDE_CAMERA.y + side * SIDE_CAMERA.z
	)
	camera.look_at(feet + forward * SIDE_TARGET_FORWARD + Vector3.UP * 0.5)
	camera.make_current()


## Whether the run was asked for `word`: on the command line after `--`, or in the page's address.
func _asked(word: String) -> bool:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.search")).contains(word)
	return OS.get_cmdline_user_args().has(word)


## For a browser probe (`tools/web_smoke/grenade_pack.py`): the stage the run is in and, at the end,
## what it measured, as `window.__pack`.
func _publish(stage: String, done := false) -> void:
	if not OS.has_feature("web"):
		return
	var gaps: Array[float] = []
	for i in range(1, _beeps.size()):
		gaps.append(snappedf(_beeps[i] - _beeps[i - 1], 0.001))
	var data := {"stage": stage, "done": done, "beeps": _beeps.size(), "gaps": gaps}
	var struck := _first(&"grenade_struck")
	data["struck"] = struck.get("zombie_id", -1)
	data["exploded"] = _exploded()
	JavaScriptBridge.eval("window.__pack = %s" % JSON.stringify(data))


func _tick() -> void:
	await get_tree().physics_frame
	_clock += Night.STEP


func _wait(frames: int) -> void:
	for _i in frames:
		await _tick()


func _exploded() -> bool:
	return not _first(&"grenade_exploded").is_empty()


func _blast_time() -> float:
	return float(_first(&"grenade_exploded").get("at", 0.0))


func _on_event(event: Dictionary) -> void:
	var stamped := event.duplicate()
	stamped["at"] = _clock
	stamped["frame"] = Engine.get_frames_drawn()
	_heard.append(stamped)
	if event["type"] == &"grenade_struck":
		_stage("a zombie stops the grenade")


func _first(type: StringName) -> Dictionary:
	for event in _heard:
		if event["type"] == type:
			return event
	return {}


func _wait_for_zombies() -> void:
	for _i in 3000:
		await get_tree().physics_frame
		if _night.server.sim.zombies.size() >= PACK_SIZE:
			return


## Puts the first `PACK_SIZE` zombies in a bunch down the way the player faces.
func _stand_the_pack(yaw: float) -> Array[ZombieBody]:
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	var feet := _night.player().global_position
	var pack: Array[ZombieBody] = []
	var offsets := [
		Vector2(0.0, 0.0),
		Vector2(-0.6, 1.2),
		Vector2(0.7, 1.4),
		Vector2(-0.2, 2.3),
		Vector2(0.5, 2.6)
	]
	var index := 0
	for body: ZombieBody in _night.server.sim.zombies.values():
		if index >= PACK_SIZE:
			break
		var offset: Vector2 = offsets[index]
		var spot := feet + forward * (PACK_FRONT + offset.y) + side * offset.x
		spot.y = body.position.y
		_spots[body] = spot
		pack.append(body)
		index += 1
	return pack


func _hold_the_pack() -> void:
	if _exploded():
		return
	for body: ZombieBody in _spots:
		if is_instance_valid(body):
			body.position = _spots[body]
			body.velocity = Vector3.ZERO


func _report(pack: Array[ZombieBody]) -> void:
	var struck := _first(&"grenade_struck")
	var blast := _first(&"grenade_exploded")
	var gaps: Array[float] = []
	for i in range(1, _beeps.size()):
		gaps.append(snappedf(_beeps[i] - _beeps[i - 1], 0.001))
	print("struck zombie %s" % struck.get("zombie_id", -1))
	if not struck.is_empty():
		var state: Dictionary = struck["state"]
		print("grenade at the strike: %s" % [state["position"]])
	print(
		(
			"blast at %s, killed %d of %d"
			% [blast.get("point", Vector3.ZERO), _killed(pack), pack.size()]
		)
	)
	print("beeps: %d, gaps %s" % [_beeps.size(), gaps])
	print("beep times %s" % [_beeps])
	# For `tools/audio/beep_report.py --frames`: the movie frames the fuse ran from the pin to the
	# blast.
	print("FUSE_FRAMES %d %d" % [_first(&"cook_started").get("frame", 0), blast.get("frame", 0)])


func _killed(pack: Array[ZombieBody]) -> int:
	var killed := 0
	for body in pack:
		if not is_instance_valid(body) or not _night.server.rules.has_zombie(body.id):
			killed += 1
	return killed


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


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])
	_publish(stage)
