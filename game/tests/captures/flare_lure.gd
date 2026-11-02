extends Node
## A person fires a flare in the night (#439), from the player's own shoulder camera with the HUD:
## the flare lands and burns, and a zombie put near it walks to it instead of to the player. Not
## part of the game. Run with Movie Maker:
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
## The zombie is put this far to the side of the flare, so it is seen walking to it (m).
const STANDOFF := 5.0
const WATCH_SECONDS := 6

var _night: Night
var _heard: Array[Dictionary] = []


func _ready() -> void:
	# The body captures the mouse when it enters the tree; a recording must never hold the cursor
	# of the person at the machine, so it is told first.
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
	_night.state.event_received.connect(_heard.append)
	_do(CombatAction.give_weapon(1, &"flare_gun"))
	_do(CombatAction.equip(1, &"flare_gun"))
	var zombie_id := await _first_zombie()
	await _wait(SECOND * 3)
	_stage("ready, flare gun in hand")
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
	var body: ZombieBody = _night.server.sim.zombies[zombie_id]
	body.enter(ZombieBody.Mode.CHASE)
	body.position = at + Basis(Vector3.UP, yaw + PI * 0.5) * Vector3.FORWARD * STANDOFF
	body.velocity = Vector3.ZERO
	await _wait(SECOND * WATCH_SECONDS)
	var gap := Vector2(body.position.x - at.x, body.position.z - at.z).length()
	_stage(
		(
			"end: the zombie is %.1f m from the flare, damage events %d"
			% [gap, _count(&"damage_dealt")]
		)
	)
	get_tree().quit()


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


func _first_zombie() -> int:
	for _i in 900:
		await get_tree().physics_frame
		if not _night.server.sim.zombies.is_empty():
			return _night.server.sim.zombies.keys()[0]
	return -1


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
