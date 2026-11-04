extends Node
## The prize crane's beam from the shoulder camera at every crane spot of both maps (#911): from
## the floor in front of the crane looking up, from the first floor or roof over it looking at the
## beam's foot, and from across the lot. Each view is drawn with the game frozen. Not part of the
## game; run it windowed:
##
##   gds godot -- --path game res://tests/captures/box_beam_views.tscn -- --out=<folder>
##       [--map=drive_in|smallmap] [--spot=<n>]
##
## Writes `<map>_<spot>_<view>.png` and prints the beam's length and what ended it.

const MAPS := {
	"drive_in": "res://world/drive_in_greybox.tscn",
	"smallmap": "res://world/smallmap/smallmap_greybox.tscn",
}
const SETTLE := 30
const SEED := 5
const CIRCUITS := [&"screen_lot", &"concession", &"booth", &"back_lot", &"mains", &"battery"]
## How far in front of the crane the floor view stands, and how far the roof view stands off.
const FRONT := 3.2
const OVER_OFF := 3.0
const ACROSS := 22.0
const EYE_PITCH_UP := deg_to_rad(28.0)

var _night: Night
var _out := "user://beam"
var _only_map := ""
var _only_spot := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--map="):
			_only_map = argument.trim_prefix("--map=")
		elif argument.begins_with("--spot="):
			_only_spot = int(argument.trim_prefix("--spot="))
	DirAccess.make_dir_recursive_absolute(_out)
	for map_id: String in MAPS:
		if _only_map == "" or _only_map == map_id:
			await _map(map_id)
	get_tree().quit()


func _map(map_id: String) -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 6000.0
	_night = Night.new()
	_night.scene = load(MAPS[map_id]) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	await _hold(SETTLE)
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 100000)))
	for _pass in 4:
		for item: ShopItem in rules.tuning.economy.items:
			if item.kind == ShopItem.Kind.DOOR and not rules.is_door_open(item.id):
				_night.state.apply_events(rules.apply(RulesAction.buy(1, item.id)))
	for circuit_id: StringName in CIRCUITS:
		_night.state.apply_events(rules.apply(RulesAction.set_circuit(circuit_id, true)))
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.player().camera_rig.camera().make_current()
	_night.player().camera_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_night.player().camera_rig.camera().physics_interpolation_mode = (
		Node.PHYSICS_INTERPOLATION_MODE_OFF
	)
	var spots: Array[int] = []
	for spot in _night.world.shop_spots():
		if spot["kind"] == &"crane":
			spots.append(spot["crane_spot"])
	for spot in spots:
		if _only_spot >= 0 and _only_spot != spot:
			continue
		rules.crane.spot = spot
		await _hold(SETTLE + 40)
		await _spot(map_id, spot)
	_night.queue_free()
	await _hold(5)


func _spot(map_id: String, spot: int) -> void:
	var view := _night.view.crane
	var crane := view.crane
	var space := _night.get_world_3d().direct_space_state
	var base := crane.global_position + Vector3.UP * PrizeCrane.MARQUEE_TOP
	var query := PhysicsRayQueryParameters3D.create(base, base + Vector3.UP * 60.0, 1)
	var hit := space.intersect_ray(query)
	var top := base.y + 60.0
	var what := "sky"
	if not hit.is_empty():
		top = (hit["position"] as Vector3).y
		what = (
			String((hit["collider"] as Node).get_path()).get_slice("/", -2)
			+ "/"
			+ String((hit["collider"] as Node).name)
		)
	print(
		(
			"%s spot %d: crane at %s, first solid above the marquee at %.2f m (%s), beam length %s"
			% [
				map_id,
				spot,
				crane.global_position,
				top - base.y,
				what,
				(
					str(crane.call(&"beam_length"))
					if crane.has_method(&"beam_length")
					else "36 (fixed)"
				)
			]
		)
	)
	var axis := Vector3(base.x, 0.0, base.z)
	var facing := crane.global_basis.z
	var front := Vector3(facing.x, 0.0, facing.z).normalized()
	# 1: on the floor in front of the glass, looking up the beam.
	await _shot(
		"%s_%d_floor" % [map_id, spot],
		Vector3(axis.x, crane.global_position.y + 0.05, axis.z) + front * FRONT,
		Vector3(axis.x, base.y + 3.0, axis.z)
	)
	# 2: on top of the first solid over the crane (a floor or a roof), looking at where the beam
	# rises through it.
	if not hit.is_empty():
		var off := front * OVER_OFF
		await _shot(
			"%s_%d_over" % [map_id, spot],
			Vector3(axis.x + off.x, top + 0.05, axis.z + off.z),
			Vector3(axis.x, top + 1.5, axis.z)
		)
	# 3: across the lot, level with the crane's feet, looking at the beam as a whole.
	await _shot(
		"%s_%d_across" % [map_id, spot],
		Vector3(axis.x, crane.global_position.y + 0.05, axis.z) + front * ACROSS,
		Vector3(axis.x, base.y + 8.0, axis.z)
	)


func _shot(label: String, feet: Vector3, look_at: Vector3) -> void:
	var player := _night.player()
	player.teleport(feet)
	var eye := feet + Vector3.UP * 1.6
	var dir := look_at - eye
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := atan2(dir.y, Vector2(dir.x, dir.z).length())
	player.state.facing = yaw
	player.rotation.y = yaw
	player.camera_rig.yaw = yaw
	player.camera_rig.pitch = clampf(pitch, -1.2, 1.2)
	await _hold(12)
	get_tree().paused = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
	get_tree().paused = false


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
