extends Node
## Every wall weapon from the player's own shoulder camera, with the HUD (#829): far (outside the
## prompt's reach, the silhouette alone) and near (the prompt card names and prices it), on either
## map, on a desktop or as a phone. One PNG a shot into `--out=<folder>`. Not part of the game.
##
##   gds godot -- --path game res://tests/captures/wall_silhouette_tour.tscn --resolution 1920x1080
##       -- --out=<folder> [--map=drive_in|small_indoor] [--touch] [--only=weapon_rifle]
##
## `--touch` (with a phone's `--resolution 2340x1080` or `844x390`) runs the night as a phone does.

const NIGHT := "res://ui/screens/night_screen.tscn"
const SETTLE := 30
## How far in front of its spot a far shot stands, metres: past the prompt's reach (3.2 m).
const FAR := 7.0
const FAR_MORE := 12.0
## How far to the player's left of the plaque the player stands, metres.
const ASIDE := 0.8
## How far out from the wall a look along it stands, metres, so the plaque is not edge on.
const ALLEY_OUT := 1.4

var _out := "user://wall_silhouettes"
var _map := "drive_in"
var _only := ""
var _night: Night
var _yaw := 0.0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--map="):
			_map = argument.trim_prefix("--map=")
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
	TouchMode.device_is_touch = "--touch" in OS.get_cmdline_user_args()
	UIMotion.reduced = true
	DirAccess.make_dir_recursive_absolute(_out)
	var settings := MatchSettings.new()
	settings.map = _map
	NightScreen.match_settings = settings
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	_night = screen.night
	await _night.ready_to_play
	_night.player().local_input = false
	await get_tree().create_timer(2.5).timeout
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 5000)))
	var seen := {}
	for spot in _night.world.shop_spots():
		var id: StringName = spot["shop_id"]
		if spot["kind"] not in [&"wall", &"rack"] or (_only != "" and String(id) != _only):
			continue
		var key := "%s_%d" % [id, int(spot["position"].y)]
		if seen.has(key) and _only == "":
			continue
		seen[key] = true
		await _visit(spot)
	get_tree().quit()


func _visit(spot: Dictionary) -> void:
	var id := String(spot["shop_id"]).trim_prefix("weapon_")
	if spot["position"].y > 1.0:
		id += "_up"
	var into := Vector3(sin(spot["yaw"]), 0.0, cos(spot["yaw"]))
	# The spot faces away from its wall; the player looks at the wall, so back out along `into`.
	# Stood to the player's left of the plaque, so the body is not in front of it.
	var aside := (-into).cross(Vector3.UP) * -ASIDE
	var wall_point: Vector3 = spot["position"] - into * 1.35
	for far: float in [FAR_MORE, FAR]:
		var reach := _clear_distance(spot["position"] + aside, into, far - 1.35)
		var at: Vector3 = spot["position"] + into * reach + aside
		var facing := -into
		if reach < far - 1.35 - 0.5:
			# No room out from this wall (an alley): look at it from along it.
			var along := Vector3.UP.cross(into)
			reach = _clear_distance(spot["position"], along, far)
			at = spot["position"] + along * reach + into * ALLEY_OUT
			facing = wall_point - at
			facing.y = 0.0
			facing = facing.normalized()
		_stand(at, facing)
		await _hold(SETTLE)
		print("far: %.1f m from the plaque" % at.distance_to(wall_point))
		await _shot("%s_%s_far_%d" % [_map, id, int(far)])
	_stand(spot["position"] + aside, -into)
	await _hold(SETTLE)
	await _shot("%s_%s_near" % [_map, id])


## How far from `from` along `direction` the way is open, at most `wanted`: a fence or a wall
## behind the player would put the camera against it.
func _clear_distance(from: Vector3, direction: Vector3, wanted: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * 1.2, from + Vector3.UP * 1.2 + direction * wanted
	)
	var hit := _night.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return wanted
	return maxf(0.0, from.distance_to(hit["position"]) - 3.0)


func _stand(feet: Vector3, facing: Vector3) -> void:
	var player := _night.player()
	player.teleport(feet + Vector3(0.0, 0.05, 0.0))
	_yaw = atan2(-facing.x, -facing.z)
	player.camera_rig.yaw = _yaw
	player.camera_rig.pitch = -0.05


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png"))
	print("SHOT ", label)


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
