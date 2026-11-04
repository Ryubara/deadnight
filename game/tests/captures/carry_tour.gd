extends Node
## The two-weapon carry from the player's shoulder camera, for captures (#410): the player stands
## at the shotgun on the wall (the card says what it replaces), buys it (the revolver is gone, the
## shotgun is in the hands and on the HUD), swaps to the crowbar and back, then plays the prize
## crane and takes the prize (the card says what it replaces; the weapon in hand is replaced
## again). Each stage prints `STAGE <name> <movie frame>`. Not part of the game. Run it with Movie
## Maker:
## `godot --path game res://tests/captures/carry_tour.tscn --fixed-fps 10 --write-movie out.png
## --quit-after 330`.

const HOLD := 60
const SHOULDER_PITCH := 0.16
const SPIN_TICKS := 300
const TICKS_PER_FRAME := 6

var _night: Night
var _yaw := 0.0
var _use := false
var _swap := false
var _ticks := 0


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	tuning.crane.leave_chances = PackedFloat32Array([0.0])
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	# The real mouse and keys must not turn the camera or move the body in a recording.
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 9000)))
	_night.state.apply_events(_night.server.rules.apply(RulesAction.buy(1, &"door_concession")))
	_night.player().camera_rig.camera().make_current()
	await _hold(5)
	await _wall()
	await _crane()
	get_tree().quit()


func _stage(name: String) -> void:
	print("STAGE %s %d" % [name, _ticks / TICKS_PER_FRAME])


func _spot(kind: StringName, shop_id: StringName) -> Dictionary:
	for spot in _night.world.shop_spots():
		if spot["kind"] == kind and spot["shop_id"] == shop_id:
			return spot
	return {}


func _face(toward: Vector3, standing: Vector3) -> void:
	var flat := Vector3(toward.x - standing.x, 0.0, toward.z - standing.z).normalized()
	_yaw = atan2(-flat.x, -flat.z)
	_night.player().camera_rig.yaw = _yaw
	_night.player().camera_rig.pitch = SHOULDER_PITCH


func _wall() -> void:
	var spot := _spot(&"wall", &"weapon_shotgun")
	var standing := spot["position"] as Vector3
	_night.player().teleport(standing + Vector3(0.0, 0.1, 0.0))
	# The weapon hangs on the wall ahead of the marker: the silhouette above it is at its place.
	var sign_at := _night.world.greybox.get_node("ShopProps/ShotgunSilhouette") as Node3D
	_face(sign_at.global_position, standing)
	await _hold(HOLD)
	_stage("wall card: the shotgun replaces the revolver")
	await _hold(HOLD)
	await _press_use()
	await _hold(HOLD + 30)
	_stage("bought: the revolver is gone, the shotgun is in hand")
	await _hold(30)
	await _press_swap()
	await _hold(HOLD)
	_stage("swap: the crowbar")
	await _press_swap()
	await _hold(HOLD)
	_stage("swap: the shotgun again")


func _crane() -> void:
	var crane_spot := {}
	for spot in _night.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == _night.server.rules.crane.spot:
			crane_spot = spot
	var standing := crane_spot["position"] as Vector3
	var crane_at: Vector3 = _night.view.crane.crane.global_position
	var flat := Vector3(crane_at.x - standing.x, 0.0, crane_at.z - standing.z).normalized()
	var side := Vector3(flat.z, 0.0, -flat.x) * 0.9
	_night.player().teleport(standing - flat * 1.0 + side + Vector3(0.0, 0.1, 0.0))
	_face(crane_at, standing - flat * 1.0 + side)
	await _hold(HOLD)
	await _press_use()
	await _hold(SPIN_TICKS + 60)
	_stage("crane card: the prize replaces the weapon in hand")
	await _hold(30)
	await _press_use()
	await _hold(HOLD + 60)
	_stage("taken: the prize is in hand")


func _press_use() -> void:
	_use = true
	await get_tree().physics_frame
	_ticks += 1
	_use = false


func _press_swap() -> void:
	_swap = true
	await get_tree().physics_frame
	_ticks += 1
	_swap = false


func _send() -> void:
	var command := NightCommand.new()
	command.motion.yaw = _yaw
	command.use = _use
	command.swap = _swap
	_night.link.send(command.to_dict())
	_night.player().camera_rig.yaw = _yaw


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
		_ticks += 1
