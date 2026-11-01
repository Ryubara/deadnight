extends Node
## The ammunition card after rounds are bought, for captures: the player has fired the pistol down
## to a few rounds in reserve, stands at an ammunition locker and buys. The card must show the new
## reserve at once, without a swap. The camera is a plain one beside the player. Not part of the
## game. Run it with Movie Maker: `godot --path game res://tests/captures/night_hud_ammo.tscn
## --fixed-fps 10 --write-movie out.png --quit-after 200`.

const LOW := 5
const HOLD := 60
const AFTER_BUY := 40

var _night: Night
var _camera: Camera3D
var _use := false


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_night.ticked.connect(_send)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 5000)))
	# The pistol fired down to a few rounds in reserve, as the card heard it.
	_night.server.combat.state_of(1, &"pistol").reserve = LOW
	_night.state.apply_events(_night.server.combat.apply(CombatAction.equip(1, &"pistol")))
	var at := Vector3.INF
	for spot in _night.world.shop_spots():
		if spot["kind"] == &"ammo":
			at = spot["position"]
			break
	_night.player().teleport(at + Vector3(0.0, 0.1, 0.0))
	_camera.look_at_from_position(at + Vector3(-2.3, 2.1, 3.4), at + Vector3(0.0, 1.1, -1.4))
	print("frame ", Engine.get_process_frames(), ": at the locker, reserve ", LOW)
	await _hold(HOLD)
	_use = true
	await _hold(1)
	_use = false
	print("frame ", Engine.get_process_frames(), ": bought")
	await _hold(AFTER_BUY)
	var reserve := _night.server.combat.state_of(1, &"pistol").reserve
	print("server reserve ", reserve)
	get_tree().quit()


func _send() -> void:
	var command := NightCommand.new()
	command.use = _use
	_night.link.send(command.to_dict())


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
