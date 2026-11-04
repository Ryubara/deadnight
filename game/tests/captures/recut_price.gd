extends Node
## The re-cut bench's card from the player's own camera, for the before and after captures of #909:
## the first weapon (what it costs), the same weapon once re-cut (what the bench says), and the
## second weapon (what it costs now). One PNG a shot into the folder. Not part of the game; run it
## windowed through the kit's private desktop:
##
##   gds godot -- --path game res://tests/captures/recut_price.tscn -- --out=<folder>

const LOT := "res://world/drive_in_greybox.tscn"
const SETTLE := 40
const RINGS: Array[float] = [1.8, 2.2, 2.6, 3.0]
const SPOKES := 36
const HAND := 1.1

var _night: Night
var _out := "user://recut_price"
var _scene := ""


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _build(LOT)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 20000)))
	var spot := _spot(&"upgrade", &"upgrade_weapon")
	var at: Vector3 = spot["position"]
	var back := _behind_a_wall(at)
	var facing := _front_facing(at, back)
	_stand(at, facing)
	await _hold(SETTLE)
	await _shot("1_first_weapon")
	_night.server.buy(1, &"upgrade_weapon")
	await _hold(SETTLE)
	await _shot("2_same_weapon_again")
	_night.server.combat.apply(CombatAction.give_weapon(1, &"smg"))
	await _hold(SETTLE)
	await _shot("3_second_weapon")
	_night.server.buy(1, &"upgrade_weapon")
	_night.server.combat.apply(CombatAction.give_weapon(1, &"shotgun"))
	await _hold(SETTLE)
	await _shot("4_third_weapon")
	get_tree().quit()


func _build(scene: String) -> void:
	if _night != null:
		_night.queue_free()
		await get_tree().process_frame
	for child in get_children():
		child.queue_free()
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	_night.scene = load(scene) as PackedScene
	_scene = scene
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	await _hold(SETTLE)


func _spot(kind: StringName, shop_id: StringName) -> Dictionary:
	for spot in _night.world.shop_spots():
		if spot["kind"] == kind and spot["shop_id"] == shop_id:
			return spot
	return {}


## The way to look from `from` at `to`, flat and unit length.
func _toward(from: Vector3, to: Vector3) -> Vector3:
	var along := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return along.normalized()


## Looking at the wall the thing hangs on: away from the point behind it.
func _front_facing(at: Vector3, back: Vector3) -> Vector3:
	return _toward(back, at) * -1.0 if back.is_finite() else Vector3(0.0, 0.0, 1.0)


## A standing point within reach on the far side of a wall from `at`, or `Vector3.INF`.
func _behind_a_wall(at: Vector3) -> Vector3:
	var space := _night.world.get_world_3d().direct_space_state
	for ring in RINGS:
		for i in SPOKES:
			var turn := TAU * float(i) / float(SPOKES)
			var x := at.x + sin(turn) * ring
			var z := at.z + cos(turn) * ring
			var ground := PhysicsRayQueryParameters3D.create(
				Vector3(x, at.y + 1.0, z), Vector3(x, at.y - 1.0, z), PhysicsLayers.WORLD
			)
			var floor_hit := space.intersect_ray(ground)
			if floor_hit.is_empty() or absf(floor_hit["position"].y - at.y) > 0.2:
				continue
			var feet: Vector3 = floor_hit["position"]
			var from := feet + Vector3(0.0, HAND, 0.0)
			var to := at + Vector3(0.0, HAND, 0.0)
			var wall := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
			var hit := space.intersect_ray(wall)
			var room := PhysicsRayQueryParameters3D.create(
				feet + Vector3(0.0, 0.1, 0.0), feet + Vector3(0.0, 1.8, 0.0), PhysicsLayers.WORLD
			)
			if hit.is_empty() or not space.intersect_ray(room).is_empty():
				continue
			if from.distance_to(hit["position"]) < from.distance_to(to) - 0.5:
				return feet
	return Vector3.INF


## Puts the player at `feet` looking along the flat direction `facing`, the camera behind.
func _stand(feet: Vector3, facing: Vector3) -> void:
	var player := _night.player()
	player.teleport(feet + Vector3(0.0, 0.05, 0.0))
	player.camera_rig.yaw = atan2(-facing.x, -facing.z)
	player.camera_rig.pitch = -0.08


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("SHOT ", name)


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
