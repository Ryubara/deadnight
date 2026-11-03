extends Node
## The second map's links, box, wall weapons and windows from the player's own shoulder camera and
## with the HUD, for captures (#632): the first link's offer and the open door behind it, the box
## (offer, spin, prize), a wall weapon's card, the upstairs after the stairs, the cabinet, and a
## window with the dead tearing its boards. One PNG a shot into the folder. Not part of the game;
## run it windowed through the kit's private desktop:
##
##   gds godot -- --path game res://tests/captures/smallmap_shop_tour.tscn -- --out=<folder>

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const SETTLE := 45
const SPIN_FRAMES_MAX := 900

var _night: Night
var _out := "user://smallmap_shop"
var _command_yaw := 0.0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	_night.scene = load(SCENE) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	await _hold(SETTLE)
	await _first_link()
	await _box()
	await _wall()
	await _upstairs()
	await _window()
	get_tree().quit()


func _first_link() -> void:
	_pay(450)
	var stand := _night.world.door_stands(&"door_side")[0]
	_stand(stand, Vector2(0.0, -1.0), 0.05)
	await _hold(SETTLE)
	await _shot("01_first_link_offer")
	_use()
	await _hold(SETTLE)
	await _shot("02_first_link_bought")
	# Through the door and into the side room.
	_stand(Vector3(14.0, 0.0, -2.2), Vector2(-1.0, 0.1), 0.05)
	await _hold(SETTLE)
	await _shot("03_side_room")


func _box() -> void:
	_pay(2000)
	var box := _spot(&"crane", &"")
	_stand(box["position"], Vector2(0.0, -1.0), 0.0)
	await _hold(SETTLE)
	await _shot("04_box_offer")
	_use()
	await _hold(80)
	await _shot("05_box_spin")
	for _i in SPIN_FRAMES_MAX:
		await _hold(1)
		if _night.server.rules.crane.stage == CraneState.Stage.GRAB:
			break
	await _hold(30)
	await _shot("06_box_prize")
	_use()
	await _hold(40)


func _wall() -> void:
	var spot := _spot(&"wall", &"weapon_smg")
	_stand(spot["position"], Vector2(0.0, -1.0), 0.0)
	await _hold(SETTLE)
	await _shot("07_wall_card")


func _upstairs() -> void:
	var stand := _night.world.door_stands(&"door_stairs_start")[0]
	_stand(stand, Vector2(1.0, 0.0), 0.05)
	await _hold(SETTLE)
	await _shot("08_stairs_offer")
	_use()
	await _hold(SETTLE)
	await _shot("09_stairs_bought")
	_stand(Vector3(9.5, 3.4, 3.2), Vector2(1.0, -0.2), 0.0)
	await _hold(SETTLE)
	await _shot("10_upstairs")
	var cabinet := _spot(&"wall", &"weapon_rifle")
	# Turned a little to the side, so the head is not in front of the sign.
	_stand(cabinet["position"], Vector2(-1.0, 0.55), 0.0)
	await _hold(SETTLE)
	await _shot("11_cabinet_card")


func _window() -> void:
	# The dead at an east window of the hall, tearing its boards: one risen outside it by hand.
	_night.server.rules.apply(RulesAction.skip_break())
	var id := &"start_4"
	var barricade := _night.world.barricade(id)
	var inward := barricade.inward()
	_stand(barricade.centre() + inward * 3.0, Vector2(-inward.x, -inward.z), 0.0)
	var spawn := Vector3.INF
	for point: Vector3 in _night.world.spawn_gates():
		if _night.world.spawn_gates()[point] == id:
			spawn = point
	var sim := _night.server.sim
	for i in 3:
		var zombie := sim.spawn(
			900 + i, 2.0, spawn + Vector3(0.0, 0.0, 1.2 * i - 1.2), 0.0, null, id
		)
		zombie.enter(ZombieBody.Mode.CHASE)
	await _hold(240)
	await _shot("12_window_dead")


## Puts the player at `feet` facing the horizontal direction `facing` (x, z), the camera behind.
func _stand(feet: Vector3, facing: Vector2, lift: float) -> void:
	var player := _night.player()
	player.teleport(feet + Vector3(0.0, lift + 0.05, 0.0))
	_command_yaw = atan2(-facing.x, -facing.y)
	player.camera_rig.yaw = _command_yaw
	player.camera_rig.pitch = -0.08


func _spot(kind: StringName, shop_id: StringName) -> Dictionary:
	for spot in _night.world.shop_spots():
		if spot["kind"] == kind and (shop_id == &"" or spot["shop_id"] == shop_id):
			return spot
	return {}


func _pay(points: int) -> void:
	var rules := _night.server.rules
	var short := points - rules.points_of(1)
	if short > 0:
		_night.state.apply_events(rules.apply(RulesAction.grant_points(1, short)))


func _use() -> void:
	var command := NightCommand.new()
	command.use = true
	command.motion.yaw = _command_yaw
	_night.link.send(command.to_dict())


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("SHOT ", name)


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
