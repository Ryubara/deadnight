extends Node
## The shop spots on the lot, for captures: the player stands at the shotgun on the wall, the prize
## crane and an ammunition locker in turn, with the HUD card, then buys. The camera is a plain one
## beside the player so the plaque, the crate and the card read together. Not part of the game.
## Run it with Movie Maker: `godot --path game res://tests/captures/shop_spots_tour.tscn
## --fixed-fps 10 --write-movie out.png --quit-after 400 -- [--bare] [--only=avenue]`. `--bare`
## takes the shop props away (the "before" of the avenue); `--only=avenue` is one still of it.

const HOLD := 60
const AFTER_BUY := 40
const SKY := Color(0.02, 0.03, 0.06)

var _night: Night
var _camera: Camera3D
var _yaw := 0.0
var _use := false
var _args := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_args[arg.trim_prefix("--").get_slice("=", 0)] = (
			arg.get_slice("=", 1) if "=" in arg else "1"
		)
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
	if _args.has("bare"):
		_night.world.greybox.get_node("ShopProps").queue_free()
	if _args.get("only", "") == "avenue":
		await _avenue()
	else:
		await _tour()
	get_tree().quit()


func _tour() -> void:
	await _visit(&"weapon_shotgun", &"", Vector3(0.0, 0.0, 1.0), "shotgun on the wall")
	await _visit(&"", &"ammo", Vector3(1.0, 0.0, 0.0), "a locker in the avenue")
	await _visit(&"crane_play", &"", Vector3(-1.0, 0.0, 0.0), "the prize crane")
	await _visit(&"weapon_rifle", &"", Vector3(0.0, 0.0, 1.0), "rifle on the booth wall")


func _avenue() -> void:
	_night.player().teleport(Vector3(0.0, 0.1, -41.0))
	_yaw = PI
	_camera.look_at_from_position(Vector3(-2.0, 2.4, -39.0), Vector3(2.5, 1.0, -28.0))
	await _hold(HOLD)


## Stands at a spot facing `facing`, shows the card, buys, shows what came of it.
func _visit(shop_id: StringName, kind: StringName, facing: Vector3, what: String) -> void:
	var at := Vector3.INF
	for spot in _night.world.shop_spots():
		if (shop_id == &"" or spot["shop_id"] == shop_id) and (kind == &"" or spot["kind"] == kind):
			at = spot["position"]
			if kind == &"ammo":
				break
	_yaw = atan2(-facing.x, -facing.z)
	_night.player().teleport(at + Vector3(0.0, 0.1, 0.0))
	var side := facing.cross(Vector3.UP)
	_camera.look_at_from_position(
		at - facing * 3.4 + side * 2.3 + Vector3(0.0, 2.1, 0.0),
		at + facing * 1.4 + Vector3(0.0, 1.1, 0.0)
	)
	print("frame ", Engine.get_process_frames(), ": ", what)
	await _hold(HOLD)
	_use = true
	await _hold(1)
	_use = false
	print("frame ", Engine.get_process_frames(), ": bought")
	await _hold(AFTER_BUY)


func _send() -> void:
	var command := NightCommand.new()
	command.motion.yaw = _yaw
	command.use = _use
	_night.link.send(command.to_dict())


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
