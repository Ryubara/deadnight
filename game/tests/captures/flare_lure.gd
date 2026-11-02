extends Node
## A person fires a flare in the night (#439), from the player's own shoulder camera with the HUD,
## then the view goes overhead: the flare lands and burns, and zombies put to either side of it
## (well off the line to the player) turn and walk to it instead of to the player. Not part of
## the game. Run with Movie Maker:
## `gds godot -- --path game res://tests/captures/flare_lure.tscn --fixed-fps 10
## --write-movie out.png --quit-after 300`.
## Each stage prints its name and the movie frame it began on.

const SECOND := 60
const SCAN_STEPS := 36
const SCAN_REACH := 40.0
const SCAN_HEIGHT := 1.0
## The flare leaves the muzzle this far above level (rise over run); below, it lands near.
const LOFT := -0.22
const FLIGHT_LIMIT := 400
## The zombies are put this far to either side of the flare, across the line to the player (m).
const STANDOFFS: Array[float] = [8.0, -8.0, 10.0, -10.0]
## The overhead camera: this high over the flare and this far back toward the player (m).
const OVERHEAD_HEIGHT := 17.0
const OVERHEAD_BACK := 3.0
const OVERHEAD_FOV := 50.0
## Long enough for the lure to end (8 s) and the zombies to turn back to the player.
const WATCH_SECONDS := 13

var _night: Night
var _hud: Hud
var _heard: Array[Dictionary] = []


func _ready() -> void:
	# The body captures the mouse when it enters the tree; a recording must never hold the cursor
	# of the person at the machine, so it is told first.
	get_tree().node_added.connect(_keep_the_mouse_free)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	await get_tree().physics_frame
	var rig := _night.player().camera_rig
	var yaw := _open_yaw()
	rig.yaw = yaw
	rig.snap_to(_night.player().global_position)
	_night.state.event_received.connect(_heard.append)
	_do(CombatAction.give_weapon(1, &"flare_gun"))
	_do(CombatAction.equip(1, &"flare_gun"))
	await _zombies_up(STANDOFFS.size())
	await _wait(SECOND * 3)
	_stage(
		(
			"ready: the ammunition card says %s, the equipment slot %s"
			% [_hud.state.weapon_name, _hud.state.equipment_name]
		)
	)
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var ahead := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	_do(
		CombatAction.fire(
			1, 1, eye, (ahead + Vector3.UP * LOFT).normalized(), eye, _night.server.combat.now
		)
	)
	_stage("fired")
	for _i in FLIGHT_LIMIT:
		if not _of(&"lure_started").is_empty():
			break
		await get_tree().physics_frame
	var lure := _of(&"lure_started")
	if lure.is_empty():
		_stage("end: the flare never burst")
		get_tree().quit()
		return
	_stage("the flare burns, lasts %.0f s" % lure[0]["seconds"])
	print(
		(
			"player %s yaw %.2f flare at %s camera looks %s"
			% [
				_night.player().global_position,
				yaw,
				lure[0]["point"],
				-_night.get_viewport().get_camera_3d().global_basis.z
			]
		)
	)
	var at: Vector3 = lure[0]["point"]
	var from_player := _night.player().global_position
	var across := Vector3(at.z - from_player.z, 0.0, from_player.x - at.x).normalized()
	var bodies: Array[ZombieBody] = []
	for i in STANDOFFS.size():
		var body: ZombieBody = _night.server.sim.zombies.values()[i]
		body.enter(ZombieBody.Mode.CHASE)
		body.position = at + across * STANDOFFS[i]
		body.velocity = Vector3.ZERO
		bodies.append(body)
	_overhead(at, from_player)
	_stage("overhead: %d zombies across the line to the player" % bodies.size())
	for second in WATCH_SECONDS:
		await _wait(SECOND)
		print("t+%2d s: %s" % [second + 1, _distances(bodies, at, from_player)])
	_stage("end: %d damage events" % _count(&"damage_dealt"))
	get_tree().quit()


## Each zombie's distance to the flare / to the player, in metres.
func _distances(bodies: Array[ZombieBody], at: Vector3, player_at: Vector3) -> String:
	var parts: PackedStringArray = []
	for body in bodies:
		parts.append("%.1f/%.1f" % [_flat(body.position, at), _flat(body.position, player_at)])
	return " ".join(parts)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A camera straight down over the flare, the player at the bottom of the picture.
func _overhead(at: Vector3, player_at: Vector3) -> void:
	var camera := Camera3D.new()
	camera.fov = OVERHEAD_FOV
	add_child(camera)
	var back := Vector3(player_at.x - at.x, 0.0, player_at.z - at.z).normalized()
	camera.global_position = at + back * OVERHEAD_BACK + Vector3.UP * OVERHEAD_HEIGHT
	camera.look_at(at + back * OVERHEAD_BACK, -back)
	camera.make_current()


## One combat action to the server; its events go to the client.
func _do(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.combat.apply(action))


func _of(type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in _heard:
		if event["type"] == type:
			found.append(event)
	return found


func _count(type: StringName) -> int:
	return _of(type).size()


func _keep_the_mouse_free(node: Node) -> void:
	if node is Player:
		(node as Player).capture_mouse = false


## The way the player can see furthest (the flare flies a while before it meets a wall).
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


## Waits until `count` zombies are in the night.
func _zombies_up(count: int) -> void:
	for _i in 1800:
		await get_tree().physics_frame
		if _night.server.sim.zombies.size() >= count:
			return


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
